import SwiftUI

struct SpeakerDiarizationImportControls<ControlsLayout: Layout>: View {
    let layout: ControlsLayout
    let canRunDiarization: Bool
    let isBusy: Bool
    let importModelAction: () -> Void
    let importMediaAction: () -> Void
    let runAction: () -> Void

    var body: some View {
        layout {
            Button("Choose CAM++", systemImage: "shippingbox", action: importModelAction)
                .disabled(isBusy)
            Button("Choose Audio or Video", systemImage: "waveform", action: importMediaAction)
                .disabled(isBusy)
            Button("Run Diarization", systemImage: "person.2.wave.2", action: runAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canRunDiarization)
        }
    }
}
