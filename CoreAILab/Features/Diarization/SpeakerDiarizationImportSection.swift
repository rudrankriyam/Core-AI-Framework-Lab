import SwiftUI

struct SpeakerDiarizationImportSection: View {
    let canRunDiarization: Bool
    let canImportModel: Bool
    let canImportMedia: Bool
    let importModelAction: () -> Void
    let importMediaAction: () -> Void
    let runAction: () -> Void

    var body: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                SpeakerDiarizationImportControls(
                    layout: HStackLayout(),
                    canRunDiarization: canRunDiarization,
                    canImportModel: canImportModel,
                    canImportMedia: canImportMedia,
                    importModelAction: importModelAction,
                    importMediaAction: importMediaAction,
                    runAction: runAction
                )
                SpeakerDiarizationImportControls(
                    layout: VStackLayout(alignment: .leading),
                    canRunDiarization: canRunDiarization,
                    canImportModel: canImportModel,
                    canImportMedia: canImportMedia,
                    importModelAction: importModelAction,
                    importMediaAction: importMediaAction,
                    runAction: runAction
                )
            }

            Text("The bundled Apache-2.0 CAM++ model runs through Core AI after 16 kHz decode, energy segmentation, and six-second feature preparation; cosine clustering produces anonymous speaker turns.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Inputs", systemImage: "waveform.and.mic")
        }
    }
}
