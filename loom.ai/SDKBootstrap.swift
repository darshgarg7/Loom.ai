import Foundation
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

@MainActor
final class SDKBootstrap {
    static let shared = SDKBootstrap()

    private(set) var isInitialized = false

    private init() {}

    func initializeIfNeeded() throws {
        if isInitialized {
            print("[SDKBootstrap] initializeIfNeeded skipped: already initialized")
            return
        }

        print("[SDKBootstrap] initializeIfNeeded started")

        // Register runtime modules before using SDK capabilities.
        print("[SDKBootstrap] RunAnywhere.initialize(environment: .development) starting")
        try RunAnywhere.initialize(environment: .development)
        print("[SDKBootstrap] RunAnywhere.initialize completed")

        print("[SDKBootstrap] Registering modules: LlamaCPP + ONNX")
        LlamaCPP.register()
        ONNX.register()
        print("[SDKBootstrap] Modules registered")

        VoiceModelService.registerDefaultModels()

        print("SDK Version: \(RunAnywhere.version)")
        isInitialized = true
        print("[SDKBootstrap] initializeIfNeeded finished")
    }
}
