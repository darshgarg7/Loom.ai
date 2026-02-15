import Foundation
import Observation

@MainActor
@Observable
final class DemoViewModel {
    enum Mode: String {
        case idle
        case listening
        case whispering
    }

    let pack: PatientPack

    var mode: Mode = .idle
    var isPreparing = false
    var isReady = false
    var isMicLocked = false
    var errorMessage: String?

    private let triggerEngine: TriggerEngine
    private let speechController = SpeechController()
    private let whisperSpeaker = WhisperSpeaker()

    private var transcriptBuffer = ""
    private var holdActive = false

    init(pack: PatientPack) {
        self.pack = pack
        self.triggerEngine = TriggerEngine(pack: pack)

        speechController.onPartialTranscript = { [weak self] partial in
            Task { @MainActor [weak self] in
                self?.handlePartialTranscript(partial)
            }
        }

        speechController.onError = { [weak self] error in
            Task { @MainActor [weak self] in
                self?.errorMessage = error.localizedDescription
                self?.holdActive = false
                self?.triggerEngine.endHold()
                self?.isMicLocked = false
                self?.mode = .idle
            }
        }
    }

    func prepare() async {
        do {
            try await ensureReady()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func holdPressed() {
        guard !isMicLocked else { return }
        guard !holdActive else { return }

        holdActive = true
        Task {
            do {
                try await ensureReady()
                guard holdActive else { return }

                transcriptBuffer = ""
                mode = .listening
                triggerEngine.beginHold()
                try await speechController.startListening()
            } catch {
                errorMessage = error.localizedDescription
                mode = .idle
                holdActive = false
                triggerEngine.endHold()
            }
        }
    }

    func stopAll() {
        holdActive = false
        speechController.stopListening()
        Task { await whisperSpeaker.stop() }
        triggerEngine.endHold()
        isMicLocked = false
        mode = .idle
    }

    private func handlePartialTranscript(_ partial: String) {
        guard holdActive else { return }
        guard !isMicLocked else { return }

        transcriptBuffer = mergeTranscript(existing: transcriptBuffer, incoming: partial)

        guard let match = triggerEngine.evaluate(rollingTranscript: transcriptBuffer) else {
            return
        }

        triggerAndWhisper(match)
    }

    private func triggerAndWhisper(_ match: TriggerMatch) {
        isMicLocked = true
        holdActive = false
        speechController.stopListening()
        triggerEngine.endHold()

        Task {
            mode = .whispering
            do {
                try await whisperSpeaker.speak(match.whisperText)
            } catch {
                errorMessage = error.localizedDescription
            }

            isMicLocked = false
            mode = .idle
        }
    }

    private func mergeTranscript(existing: String, incoming: String) -> String {
        let newText = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newText.isEmpty else { return existing }

        if existing.isEmpty {
            return newText
        }

        if newText.hasPrefix(existing) {
            return newText
        }

        if existing.hasSuffix(newText) {
            return existing
        }

        let merged = "\(existing) \(newText)"
        let maxChars = 420
        if merged.count <= maxChars {
            return merged
        }

        return String(merged.suffix(maxChars))
    }

    private func ensureReady() async throws {
        if isReady { return }

        if isPreparing {
            while isPreparing {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            if isReady { return }
            throw DemoSetupError.notReady
        }

        isPreparing = true
        defer { isPreparing = false }

        try SDKBootstrap.shared.initializeIfNeeded()
        try await VoiceModelService.shared.ensureSTTReady()
        try await VoiceModelService.shared.ensureTTSReady()

        let granted = await speechController.requestMicPermission()
        guard granted else {
            throw DemoSetupError.microphonePermissionDenied
        }

        isReady = true
    }
}

enum DemoSetupError: LocalizedError {
    case microphonePermissionDenied
    case notReady

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone permission denied. Enable it in Settings."
        case .notReady:
            return "Speech models are still loading. Please try again."
        }
    }
}
