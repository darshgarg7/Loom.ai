import AVFoundation
import Foundation
import RunAnywhere

final class SpeechController {
    enum State: Equatable {
        case idle
        case listening
    }

    var onPartialTranscript: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var state: State = .idle

    private let audioEngine = AVAudioEngine()
    private let recognitionQueue = DispatchQueue(label: "SpeechController.recognition")

    private var recognitionTask: Task<Void, Never>?
    private var analysisTimer: Timer?
    private var pcmData = Data()
    private var lastPartial = ""

    private let sampleRate: Double = 16_000
    private let chunkWindowSeconds: Double = 2.4

    func requestMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startListening() async throws {
        guard state == .idle else { return }

        try configureSessionForListening()

        resetBuffers()

        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true)
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard let targetFormat = format else {
            throw SpeechControllerError.invalidFormat
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let converted = self.convertToPCM16Mono(buffer: buffer, to: targetFormat) else { return }
            self.recognitionQueue.async {
                self.pcmData.append(converted)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        state = .listening
        startAnalysisLoop()
    }

    private func configureSessionForListening() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
            try session.setActive(true)
        } catch {
            // Fallback for devices/routes that reject the richer option set.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        }
    }

    func stopListening() {
        guard state == .listening else { return }

        stopAnalysisLoop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        state = .idle
    }

    private func startAnalysisLoop() {
        stopAnalysisLoop()
        analysisTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            self?.schedulePartialRecognition()
        }
    }

    private func stopAnalysisLoop() {
        analysisTimer?.invalidate()
        analysisTimer = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func schedulePartialRecognition() {
        guard state == .listening else { return }
        guard recognitionTask == nil else { return }

        let windowBytes = Int(sampleRate * chunkWindowSeconds) * 2

        recognitionTask = Task { [weak self] in
            guard let self else { return }

            let chunk: Data = self.recognitionQueue.sync {
                if self.pcmData.count <= windowBytes {
                    return self.pcmData
                }
                return self.pcmData.suffix(windowBytes)
            }

            defer {
                DispatchQueue.main.async {
                    self.recognitionTask = nil
                }
            }

            guard chunk.count > 1_500 else { return }
            guard !Task.isCancelled else { return }

            do {
                let partial = try await RunAnywhere.transcribe(chunk).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !Task.isCancelled else { return }
                guard !partial.isEmpty else { return }
                guard partial != self.lastPartial else { return }

                self.lastPartial = partial
                DispatchQueue.main.async {
                    self.onPartialTranscript?(partial)
                }
            } catch {
                guard !Task.isCancelled else { return }
                DispatchQueue.main.async {
                    self.onError?(error)
                }
            }
        }
    }

    private func resetBuffers() {
        recognitionQueue.sync {
            pcmData.removeAll(keepingCapacity: true)
        }
        lastPartial = ""
    }

    private func convertToPCM16Mono(buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> Data? {
        let converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        guard let converter else { return nil }

        let frameCapacity = AVAudioFrameCount(targetFormat.sampleRate / buffer.format.sampleRate * Double(buffer.frameLength)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return nil }

        var didProvideInput = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if conversionError != nil {
            return nil
        }

        guard let channels = output.int16ChannelData else { return nil }
        let samples = Int(output.frameLength)
        return Data(bytes: channels[0], count: samples * MemoryLayout<Int16>.size)
    }
}

enum SpeechControllerError: LocalizedError {
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Unable to configure microphone recording format."
        }
    }
}
