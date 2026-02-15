import Foundation

struct PatientPack: Codable, Identifiable, Hashable {
    struct Patient: Codable, Hashable {
        let id: String
        let displayName: String
    }

    struct Defaults: Codable, Hashable {
        let delayGateMs: Int
        let oneTriggerPerHold: Bool
        let globalVetoPhrases: [String]
    }

    struct Trigger: Codable, Identifiable, Hashable {
        let id: String
        let label: String
        let mustIncludeAny: [String]
        let contextAny: [String]
        let cooldownSeconds: TimeInterval
        let whisperText: String
    }

    let version: Int
    let packId: String
    let patient: Patient
    let defaults: Defaults
    let triggers: [Trigger]

    var id: String { packId }
}
