import SwiftUI

struct ContentView: View {
    @State private var selection = CoreAILabTab.synthesize

    var body: some View {
        TabView(selection: $selection) {
            Tab("Synthesize", systemImage: "waveform", value: .synthesize) {
                ChatterboxWorkspaceView()
            }

            Tab("Core AI", systemImage: "cpu", value: .runtime) {
                CoreAIRuntimeView()
            }
        }
    }
}

#Preview {
    ContentView()
}
