import Foundation

struct TriggerMatch: Equatable {
    let whisperText: String
}

@MainActor
final class TriggerEngine {
    private let pack: PatientPack
    private var holdStartedAt: Date?
    private var firedInCurrentHold = false
    private var lastFiredByTriggerId: [String: Date] = [:]

    init(pack: PatientPack) {
        self.pack = pack
    }

    func beginHold(at date: Date = Date()) {
        holdStartedAt = date
        firedInCurrentHold = false
    }

    func endHold() {
        holdStartedAt = nil
        firedInCurrentHold = false
    }

    func evaluate(rollingTranscript: String, at now: Date = Date()) -> TriggerMatch? {
        guard let startedAt = holdStartedAt else { return nil }

        // 1) Delay gate.
        let elapsedMs = now.timeIntervalSince(startedAt) * 1000
        guard elapsedMs >= Double(pack.defaults.delayGateMs) else { return nil }

        // 2) One trigger per hold session.
        if pack.defaults.oneTriggerPerHold && firedInCurrentHold { return nil }

        let normalized = Self.normalize(rollingTranscript)
        guard !normalized.isEmpty else { return nil }

        // 3) Veto phrases.
        if containsAnyPhrase(in: normalized, phrases: pack.defaults.globalVetoPhrases) {
            return nil
        }

        for trigger in pack.triggers {
            // 4) Cooldown per trigger.
            if let lastFired = lastFiredByTriggerId[trigger.id],
               now.timeIntervalSince(lastFired) < trigger.cooldownSeconds {
                continue
            }

            // 5) Context rule requires both mustIncludeAny AND contextAny.
            let hasMust = containsAnyPhrase(in: normalized, phrases: trigger.mustIncludeAny)
            let hasContext = containsAnyPhrase(in: normalized, phrases: trigger.contextAny)

            guard hasMust && hasContext else { continue }

            firedInCurrentHold = true
            lastFiredByTriggerId[trigger.id] = now
            return TriggerMatch(whisperText: trigger.whisperText)
        }

        return nil
    }

    static func normalize(_ text: String) -> String {
        // Fold case/diacritics first so matching is resilient to transcription variants.
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)

        // Normalize apostrophe-like characters.
        let deapostrophized = folded.replacingOccurrences(
            of: "[’'`]",
            with: "",
            options: .regularExpression
        )

        let cleaned = deapostrophized.replacingOccurrences(
            of: "[^a-z0-9\\s]",
            with: " ",
            options: .regularExpression
        )
        let collapsed = cleaned.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func containsAnyPhrase(in normalizedTranscript: String, phrases: [String]) -> Bool {
        phrases
            .map(Self.normalize)
            .contains { phrase in
                guard !phrase.isEmpty else { return false }
                return normalizedTranscript.contains(phrase)
            }
    }
}
