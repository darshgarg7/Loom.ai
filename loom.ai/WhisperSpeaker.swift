import AVFoundation
import Foundation
import RunAnywhere

@MainActor
final class WhisperSpeaker {
    private(set) var isSpeaking = false

    func speak(_ text: String) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        try configureSessionForWhisper()

        isSpeaking = true
        defer { isSpeaking = false }

        _ = try await RunAnywhere.speak(makeSlightlySlower(text))
    }

    func stop() async {
        await RunAnywhere.stopSpeaking()
        isSpeaking = false
    }

    private func configureSessionForWhisper() throws {
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try session.setActive(true)
        } catch {
            // Conservative fallback if route/category options are rejected.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        }
    }

    private func makeSlightlySlower(_ text: String) -> String {
        // Normalize spacing and add small pause markers at phrase boundaries.
        let compact = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compact.isEmpty else { return text }

        let withPauses = compact
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: ";", with: "; ")
            .replacingOccurrences(of: " and ", with: ", and ")
            .replacingOccurrences(of: " but ", with: ", but ")

        if withPauses.hasSuffix(".") || withPauses.hasSuffix("!") || withPauses.hasSuffix("?") {
            return withPauses
        }

        return withPauses + "."
    }
}
