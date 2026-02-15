import Foundation
import RunAnywhere

@MainActor
final class VoiceModelService {
    static let shared = VoiceModelService()

    static let llmModelId = "lfm2-350m-q4_k_m"
    static let sttModelId = "sherpa-onnx-whisper-tiny.en"
    static let ttsModelId = "vits-piper-en_US-lessac-medium"

    private static var didRegisterModels = false

    private init() {}

    static func registerDefaultModels() {
        guard !didRegisterModels else {
            print("[VoiceModelService] model registration skipped: already registered")
            return
        }

        print("[VoiceModelService] registering default voice models")

        if let lfm2URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: llmModelId,
                name: "LiquidAI LFM2 350M Q4_K_M",
                url: lfm2URL,
                framework: .llamaCpp,
                memoryRequirement: 250_000_000
            )
        }

        if let whisperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz") {
            RunAnywhere.registerModel(
                id: sttModelId,
                name: "Sherpa Whisper Tiny (ONNX)",
                url: whisperURL,
                framework: .onnx,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 75_000_000
            )
        }

        if let piperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: ttsModelId,
                name: "Piper TTS (US English - Medium)",
                url: piperURL,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }

        didRegisterModels = true
        print("[VoiceModelService] voice models registered")
    }

    func ensureLLMReady() async throws {
        print("[VoiceModelService] LLM: checking cache")
        do {
            try await RunAnywhere.loadModel(Self.llmModelId)
            print("[VoiceModelService] LLM: loaded from cache")
            return
        } catch {
            print("[VoiceModelService] LLM: cache miss, downloading")
        }

        try await downloadModel(Self.llmModelId, label: "LLM")

        try await RunAnywhere.loadModel(Self.llmModelId)
        print("[VoiceModelService] LLM: loaded after download")
    }

    func ensureSTTReady() async throws {
        print("[VoiceModelService] STT: checking cache")
        do {
            try await RunAnywhere.loadSTTModel(Self.sttModelId)
            print("[VoiceModelService] STT: loaded from cache")
            return
        } catch {
            print("[VoiceModelService] STT: cache miss, downloading")
        }

        try await downloadModel(Self.sttModelId, label: "STT")

        try await RunAnywhere.loadSTTModel(Self.sttModelId)
        print("[VoiceModelService] STT: loaded after download")
    }

    func ensureTTSReady() async throws {
        print("[VoiceModelService] TTS: checking cache")
        do {
            try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
            print("[VoiceModelService] TTS: loaded from cache")
            return
        } catch {
            print("[VoiceModelService] TTS: cache miss, downloading")
        }

        try await downloadModel(Self.ttsModelId, label: "TTS")

        try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
        print("[VoiceModelService] TTS: loaded after download")
    }

    private func downloadModel(_ modelId: String, label: String) async throws {
        let progressStream = try await RunAnywhere.downloadModel(modelId)
        var lastBucket = -1

        for await progress in progressStream {
            let pct = Int(progress.overallProgress * 100)
            let bucket = pct / 10
            if bucket > lastBucket || progress.stage == .completed {
                print("[VoiceModelService] \(label): download \(pct)% (\(progress.stage))")
                lastBucket = bucket
            }
            if progress.stage == .completed { break }
        }
    }
}
