import SwiftUI

struct CoreAIFunctionResultsView: View {
    let result: CoreAIFunctionRunResult

    var body: some View {
        Section {
            LabeledContent("Function", value: result.functionName)
            LabeledContent("Inference time") {
                Text(result.duration.formatted(.time(pattern: .minuteSecond)))
            }
            ForEach(result.outputs) { output in
                CoreAIFunctionOutputSummaryView(output: output)
            }
        } header: {
            Label("Latest Run", systemImage: "checkmark.circle")
        }
    }
}
