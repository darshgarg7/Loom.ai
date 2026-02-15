import Foundation

// Check PackDecode
enum ScenarioPackDecodeError: LocalizedError {
    case missingTriggerPackContainer
    case missingRequiredField(String)
    case unsupportedScenarioShape

    var errorDescription: String? {
        switch self {
        case .missingTriggerPackContainer:
            return "Scenario JSON is missing a trigger pack container. Expected one of: triggerPack, pack, scenario.triggerPack, scenario.pack, data.triggerPack, data.pack."
        case let .missingRequiredField(field):
            return "Scenario trigger pack is missing required field: \(field)."
        case .unsupportedScenarioShape:
            return "Scenario JSON shape is unsupported. Expected old trigger pack fields or suture_logic format."
        }
    }
}

// Take data from json
struct ScenarioCompatibilityEnvelope: Decodable {
    struct NestedContainer: Decodable {
        let triggerPack: TriggerPackPayload?
        let pack: TriggerPackPayload?
    }

    let triggerPack: TriggerPackPayload?
    let pack: TriggerPackPayload?
    let scenario: NestedContainer?
    let data: NestedContainer?

    func extractTriggerPackPayload() throws -> TriggerPackPayload {
        if let triggerPack { return triggerPack }
        if let pack { return pack }
        if let triggerPack = scenario?.triggerPack { return triggerPack }
        if let pack = scenario?.pack { return pack }
        if let triggerPack = data?.triggerPack { return triggerPack }
        if let pack = data?.pack { return pack }
        throw ScenarioPackDecodeError.missingTriggerPackContainer
    }
}

struct TriggerPackPayload: Decodable {
    struct Patient: Decodable {
        let id: String?
        let displayName: String?
    }

    struct Defaults: Decodable {
        let delayGateMs: Int?
        let oneTriggerPerHold: Bool?
        let globalVetoPhrases: [String]?
    }

    struct Trigger: Decodable {
        let id: String?
        let label: String?
        let mustIncludeAny: [String]?
        let contextAny: [String]?
        let cooldownSeconds: Int?
        let whisperText: String?
    }

    let version: Int?
    let packId: String?
    let patient: Patient?
    let defaults: Defaults?
    let triggers: [Trigger]?

    func toPatientPack() throws -> PatientPack {
        let version = try required(version, "version")
        let packId = try required(packId, "packId")
        let patient = try required(patient, "patient")
        let defaults = try required(defaults, "defaults")
        let triggers = try required(triggers, "triggers")

        return PatientPack(
            version: version,
            packId: packId,
            patient: .init(
                id: try required(patient.id, "patient.id"),
                displayName: try required(patient.displayName, "patient.displayName")
            ),
            defaults: .init(
                delayGateMs: try required(defaults.delayGateMs, "defaults.delayGateMs"),
                oneTriggerPerHold: try required(defaults.oneTriggerPerHold, "defaults.oneTriggerPerHold"),
                globalVetoPhrases: normalizePhrases(try required(defaults.globalVetoPhrases, "defaults.globalVetoPhrases"))
            ),
            triggers: try triggers.enumerated().map { index, trigger in
                try .init(
                    id: required(trigger.id, "triggers[\(index)].id"),
                    label: required(trigger.label, "triggers[\(index)].label"),
                    mustIncludeAny: normalizePhrases(required(trigger.mustIncludeAny, "triggers[\(index)].mustIncludeAny")),
                    contextAny: normalizePhrases(required(trigger.contextAny, "triggers[\(index)].contextAny")),
                    cooldownSeconds: TimeInterval(required(trigger.cooldownSeconds, "triggers[\(index)].cooldownSeconds")),
                    whisperText: required(trigger.whisperText, "triggers[\(index)].whisperText")
                )
            }
        )
    }

    private func required<T>(_ value: T?, _ field: String) throws -> T {
        guard let value else { throw ScenarioPackDecodeError.missingRequiredField(field) }
        return value
    }

    private func normalizePhrases(_ phrases: [String]) -> [String] {
        phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }
}

enum RichScenarioMapper {
    static func decodePatientPack(from data: Data) throws -> PatientPack {
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = raw as? [String: Any] else {
            throw ScenarioPackDecodeError.unsupportedScenarioShape
        }

        guard let sutureLogic = root["suture_logic"] as? [[String: Any]], !sutureLogic.isEmpty else {
            throw ScenarioPackDecodeError.unsupportedScenarioShape
        }

        let metadata = root["metadata"] as? [String: Any]
        let demoTitle = (root["demoTitle"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionString = metadata?["version"] as? String
        let version = Int(versionString ?? "") ?? 1

        let patientName = ((metadata?["patient"] as? String) ?? "Patient")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patientId = slug(patientName.isEmpty ? "patient" : patientName)

        let globalVeto = normalizePhrases(root["global_veto"] as? [String] ?? [])

        let triggers: [PatientPack.Trigger] = sutureLogic.enumerated().compactMap { index, item in
            let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let triggerPhrases = normalizePhrases(item["trigger_phrases"] as? [String] ?? [])
            let whisper = (item["suture_whisper"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let id, !id.isEmpty, !triggerPhrases.isEmpty, let whisper, !whisper.isEmpty else {
                return nil
            }

            let label = humanize(id: id, fallback: "Scenario Trigger \(index + 1)")
            return PatientPack.Trigger(
                id: id,
                label: label,
                mustIncludeAny: triggerPhrases,
                contextAny: triggerPhrases,
                cooldownSeconds: 90,
                whisperText: whisper
            )
        }

        guard !triggers.isEmpty else {
            throw ScenarioPackDecodeError.missingRequiredField("suture_logic[].trigger_phrases / suture_whisper")
        }

        let packId = slug((demoTitle?.isEmpty == false ? demoTitle! : "scenario-pack"))

        return PatientPack(
            version: version,
            packId: packId,
            patient: .init(id: patientId, displayName: patientName.isEmpty ? "Patient" : patientName),
            defaults: .init(
                delayGateMs: 900,
                oneTriggerPerHold: true,
                globalVetoPhrases: globalVeto
            ),
            triggers: triggers
        )
    }

    private static func normalizePhrases(_ phrases: [String]) -> [String] {
        phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        let replaced = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func humanize(id: String, fallback: String) -> String {
        let cleaned = id.replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return fallback }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }
}
