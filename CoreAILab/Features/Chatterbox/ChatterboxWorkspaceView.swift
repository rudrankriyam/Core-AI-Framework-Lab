import SwiftUI

struct ChatterboxWorkspaceView: View {
    @State private var model = ChatterboxWorkspaceModel()

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                ChatterboxModelSection(state: model.modelState)

                ChatterboxPromptSection(prompt: $model.prompt)

                ChatterboxPipelineSection(state: model.modelState)

                ChatterboxGenerationSection(
                    canGenerate: model.canGenerate,
                    isWorking: model.isWorking,
                    workingActionTitle: model.workingActionTitle,
                    statusMessage: model.statusMessage,
                    result: model.generatedResult,
                    isPlaying: model.isPlaying,
                    generateAction: model.generate,
                    playbackAction: model.togglePlayback
                )
            }
            .formStyle(.grouped)
            .navigationTitle(model.recipeManifest?.displayName ?? "Text to Speech")
            .toolbar {
#if os(macOS)
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        "Generate Speech",
                        systemImage: "play.circle.fill",
                        action: model.generate
                    )
                    .disabled(!model.canGenerate)
                    .help(model.statusMessage)
                }
#endif
            }
            .task {
                await model.prepare()
            }
            .alert(
                model.presentedError?.title ?? "Couldn't Complete the Request",
                isPresented: $model.isShowingError
            ) {
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text(model.presentedError?.message ?? "Try again.")
            }
        }
    }
}
