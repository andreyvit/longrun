import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Longrun")
                .font(.title)
        }
        .frame(minWidth: 700, minHeight: 460)
    }
}
