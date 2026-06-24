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
        } header: {
            Label("Inputs", systemImage: "waveform.and.mic")
        }
        .help(
            "Core AI runs the bundled CAM++ model after 16 kHz decode, energy segmentation, and feature preparation."
        )
    }
}
