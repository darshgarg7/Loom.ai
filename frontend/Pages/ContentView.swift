import SwiftUI

struct HomeView: View {
    @State private var index = 0
    
    private let messages = [
        "Welcome to loom.ai",
        "Weaving history into the present"
    ]
    
    let timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack {
            Text(messages[index])
                .font(Font.custom("Indie Flower", size: 64))
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .frame(width: 300, height: 200)
                .animation(.easeInOut(duration: 0.6), value: index)
        }
        .frame(width: 402)
        .background(Color(red: 0.65, green: 1, blue: 0.53))
        .cornerRadius(62)
        .onReceive(timer) { _ in
            index = (index + 1) % messages.count
        }
    }
}
