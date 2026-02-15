import SwiftUI

struct ImagePageView: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .ignoresSafeArea()
    }
}

struct FlipbookAnimationView: View {
    let frames: [String]
    let frameDuration: TimeInterval
    let loop: Bool

    @State private var index = 0
    @State private var timer: Timer?

    var body: some View {
        ImagePageView(assetName: frames[safe: index] ?? frames.first ?? "")
            .onAppear {
                timer?.invalidate()
                index = 0
                timer = Timer.scheduledTimer(withTimeInterval: frameDuration, repeats: true) { _ in
                    if index < frames.count - 1 {
                        index += 1
                    } else if loop {
                        index = 0
                    } else {
                        timer?.invalidate()
                        timer = nil
                    }
                }
            }
            .onDisappear {
                timer?.invalidate()
                timer = nil
            }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

