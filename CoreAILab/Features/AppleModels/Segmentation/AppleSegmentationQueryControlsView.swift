import SwiftUI

struct AppleSegmentationQueryControlsView: View {
    @Bindable var workspace: AppleSegmentationWorkspaceModel

    var body: some View {
        Section {
            if workspace.example.usesTextPrompt {
                TextField(
                    "Object to segment",
                    text: $workspace.textPrompt,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .help("SAM 3 uses the tokenizer bundled with the exported resource folder.")
            } else if workspace.sourceImage != nil {
                LabeledContent("Horizontal position") {
                    Text(workspace.pointX, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $workspace.pointX, in: 0...workspace.imageWidth)

                LabeledContent("Vertical position") {
                    Text(workspace.pointY, format: .number.precision(.fractionLength(0)))
                        .monospacedDigit()
                }
                Slider(value: $workspace.pointY, in: 0...workspace.imageHeight)

                .help("Coordinates use pixels from the image's top-left corner.")
            } else {
                ContentUnavailableView(
                    "Choose an Image",
                    systemImage: "point.bottomleft.forward.to.point.topright.scurvepath",
                    description: Text("Point controls appear after an image is loaded.")
                )
            }
        } header: {
            Label(
                workspace.example.usesTextPrompt ? "Text Prompt" : "Point Prompt",
                systemImage: workspace.example.usesTextPrompt ? "text.cursor" : "scope"
            )
        }
        .disabled(workspace.isBusy)
    }
}
