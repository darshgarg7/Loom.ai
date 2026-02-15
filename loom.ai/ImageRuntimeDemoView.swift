import SwiftUI

struct ImageRuntimeDemoView: View {
    private let postRuntimeAssets = [
        "ListeningScreen 1",
        "heartanimation",
        "Injestion",
        "Injestion-1",
        "Injestion-2"
    ]

    @State private var viewModel: DemoViewModel
    @State private var hasPrepared = false
    @State private var shouldAutoRestart = true
    @State private var showingPostRuntime = false
    @State private var postRuntimeIndex = 0

    init(pack: PatientPack) {
        _viewModel = State(initialValue: DemoViewModel(pack: pack))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(currentAssetName)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    handleTap()
                }
                .task {
                    guard !hasPrepared else { return }
                    hasPrepared = true
                    await viewModel.prepare()
                    shouldAutoRestart = true
                    viewModel.holdPressed()
                }
                .onChange(of: viewModel.mode) { _, newMode in
                    guard !showingPostRuntime else { return }
                    guard newMode == .idle else { return }
                    guard shouldAutoRestart else { return }
                    guard !viewModel.isPreparing else { return }
                    guard !viewModel.isMicLocked else { return }

                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard viewModel.mode == .idle else { return }
                        guard shouldAutoRestart else { return }
                        viewModel.holdPressed()
                    }
                }

            if !showingPostRuntime {
                Button("Stop Runtime") {
                    shouldAutoRestart = false
                    viewModel.stopAll()
                    showingPostRuntime = true
                    postRuntimeIndex = 0
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 16)
                .padding(.trailing, 16)
            }
        }
        .onDisappear {
            viewModel.stopAll()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("Retry") {
                shouldAutoRestart = true
                viewModel.holdPressed()
            }
            Button("Stop", role: .cancel) {
                shouldAutoRestart = false
                viewModel.stopAll()
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var currentAssetName: String {
        if showingPostRuntime {
            let safeIndex = max(0, min(postRuntimeIndex, postRuntimeAssets.count - 1))
            return postRuntimeAssets[safeIndex]
        }

        switch viewModel.mode {
        case .whispering:
            return "Talkingscreen"
        case .idle, .listening:
            return "ListeningScreen"
        }
    }

    private func handleTap() {
        if showingPostRuntime {
            let next = postRuntimeIndex + 1
            if next < postRuntimeAssets.count {
                postRuntimeIndex = next
            } else {
                showingPostRuntime = false
                postRuntimeIndex = 0
                shouldAutoRestart = true
                viewModel.holdPressed()
            }
            return
        }

        if viewModel.mode == .listening {
            shouldAutoRestart = false
            viewModel.stopAll()
        } else {
            shouldAutoRestart = true
            viewModel.holdPressed()
        }
    }
}
