import SwiftUI

struct ContentView: View {
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @State private var packs: [PatientPack] = []
    @State private var selectedPack: PatientPack?
    @State private var loadError: String?

    private let forceOnboardingForDebug = true

    var body: some View {
        NavigationStack {
            Group {
                if let selectedPack {
                    ImageRuntimeDemoView(pack: selectedPack)
                } else if !packs.isEmpty {
                    if onboardingComplete && !forceOnboardingForDebug {
                        ImageRuntimeDemoView(pack: packs[0])
                    } else {
                        OnboardingFlowView(packs: packs) { pack in
                            selectedPack = pack
                        }
                    }
                } else {
                    ProgressView("Loading patient packs...")
                }
            }
        }
        .task {
            do {
                packs = try PackLoader().loadBundledPacks()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .alert("Pack Load Error", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) {
                loadError = nil
            }
        } message: {
            Text(loadError ?? "Unknown error")
        }
    }
}

#Preview {
    ContentView()
}
