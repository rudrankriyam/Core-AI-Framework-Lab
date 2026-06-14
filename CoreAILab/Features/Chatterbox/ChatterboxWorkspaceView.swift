import SwiftUI

struct ChatterboxWorkspaceView: View {
    @State private var model = ChatterboxWorkspaceModel()

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                ChatterboxHeroView()

                ChatterboxModelSection(state: model.modelState)

                ChatterboxPromptSection(prompt: $model.prompt)

                ChatterboxPipelineSection(inspection: model.inspection)

                ChatterboxGenerationSection(
                    canGenerate: model.canGenerate,
                    isWorking: model.isWorking,
                    statusMessage: model.statusMessage,
                    result: model.generatedResult,
                    isPlaying: model.isPlaying,
                    generateAction: model.generate,
                    playbackAction: model.togglePlayback
                )
            }
            .formStyle(.grouped)
            .navigationTitle("Chatterbox")
            .task {
                await model.prepare()
            }
            .alert(item: $model.presentedError) { presentedError in
                Alert(
                    title: Text("Chatterbox Core AI"),
                    message: Text(presentedError.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}
