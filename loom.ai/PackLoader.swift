import Foundation

enum PackLoaderError: LocalizedError {
    case newScenarioMissing
    case newScenarioUnreadable
    case newScenarioInvalid(String)

    var errorDescription: String? {
        switch self {
        case .newScenarioMissing:
            return "newScenario.json was not found in the app bundle."
        case .newScenarioUnreadable:
            return "Unable to read newScenario.json from the app bundle."
        case let .newScenarioInvalid(reason):
            return "newScenario.json is invalid: \(reason)"
        }
    }
}

struct PackLoader {
    func loadBundledPacks() throws -> [PatientPack] {
        guard let url = Bundle.main.url(forResource: "newScenario", withExtension: "json", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "newScenario", withExtension: "json")
        else {
            throw PackLoaderError.newScenarioMissing
        }

        guard let data = try? Data(contentsOf: url) else {
            throw PackLoaderError.newScenarioUnreadable
        }

        do {
            let pack = try RichScenarioMapper.decodePatientPack(from: data)
            return [pack]
        } catch {
            throw PackLoaderError.newScenarioInvalid(error.localizedDescription)
        }
    }
}
