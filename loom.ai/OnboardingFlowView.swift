import SwiftUI

struct OnboardingFlowView: View {
    let packs: [PatientPack]
    let onContinue: (PatientPack) -> Void

    private let onboardingAssets = ["HomeScreen", "ConversationScreen"]
    private let loadingFrames = ["LoadingScreen1", "LoadingScreen2", "LoadingScreen3", "LoadingScreen4", "LoadingScreen5"]

    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var stepIndex = 0
    @State private var prewarmTask: Task<Void, Never>?
    @State private var didStartPrewarm = false
    @State private var isPrewarmDone = false
    @State private var prewarmError: String?

    var body: some View {
        Group {
            pageView
                .contentShape(Rectangle())
                .onTapGesture {
                    advanceOrFinish()
                }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            stepIndex = 0
            startPrewarmIfNeeded()
        }
        .onDisappear {
            prewarmTask?.cancel()
            prewarmTask = nil
        }
        .alert("Model Load Error", isPresented: Binding(
            get: { prewarmError != nil },
            set: { if !$0 { prewarmError = nil } }
        )) {
            Button("Retry") {
                didStartPrewarm = false
                isPrewarmDone = false
                startPrewarmIfNeeded()
            }
            Button("Continue", role: .cancel) {
                isPrewarmDone = true
                prewarmError = nil
            }
        } message: {
            Text(prewarmError ?? "Unknown error")
        }
    }

    private var pageView: some View {
        Group {
            if stepIndex == 0 {
                FlipbookAnimationView(
                    frames: loadingFrames,
                    frameDuration: 0.14,
                    loop: true
                )
            } else {
                let assetIndex = max(0, min(stepIndex - 1, onboardingAssets.count - 1))
                ImagePageView(assetName: onboardingAssets[assetIndex])
            }
        }
    }

    private func advanceOrFinish() {
        // While models load, keep user on the loading animation.
        if stepIndex == 0 {
            guard isPrewarmDone else { return }
            stepIndex = 1
            return
        }

        if stepIndex >= onboardingAssets.count {
            finishOnboarding()
            return
        }

        stepIndex += 1
    }

    private func startPrewarmIfNeeded() {
        guard !didStartPrewarm else { return }
        didStartPrewarm = true
        isPrewarmDone = false
        prewarmError = nil

        prewarmTask = Task { @MainActor in
            do {
                async let minDelay: Void = Task.sleep(nanoseconds: 1_200_000_000)
                async let modelLoad: Void = prewarmModels()
                _ = try await (minDelay, modelLoad)

                isPrewarmDone = true
                guard stepIndex == 0 else { return }
                stepIndex = 1
            } catch {
                prewarmError = error.localizedDescription
            }
        }
    }

    private func prewarmModels() async throws {
        try SDKBootstrap.shared.initializeIfNeeded()
        try await VoiceModelService.shared.ensureSTTReady()
        try await VoiceModelService.shared.ensureTTSReady()
    }

    private func finishOnboarding() {
        guard let selectedPack = packs.first else { return }
        onboardingComplete = true
        onContinue(selectedPack)
    }
}
