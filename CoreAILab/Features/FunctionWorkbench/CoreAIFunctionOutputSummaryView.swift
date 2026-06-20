import SwiftUI

struct CoreAIFunctionOutputSummaryView: View {
    let output: CoreAIFunctionOutputSummary

    var body: some View {
        DisclosureGroup {
            LabeledContent("Type", value: output.typeDescription)
            LabeledContent("Shape", value: output.shape.map(String.init).joined(separator: " × "))
            if !output.strides.isEmpty {
                LabeledContent(
                    "Strides",
                    value: output.strides.map(String.init).joined(separator: ", ")
                )
            }
            LabeledContent("Elements", value: output.elementCount, format: .number)
            if output.sampledElementCount > 0 {
                LabeledContent("Sampled", value: output.sampledElementCount, format: .number)
            }
            if let minimum = output.minimum,
               let maximum = output.maximum,
               let mean = output.mean {
                LabeledContent("Minimum") {
                    Text(minimum, format: .number.precision(.significantDigits(6)))
                }
                LabeledContent("Maximum") {
                    Text(maximum, format: .number.precision(.significantDigits(6)))
                }
                LabeledContent("Mean") {
                    Text(mean, format: .number.precision(.significantDigits(6)))
                }
                LabeledContent("NaN or infinity", value: output.nonFiniteCount, format: .number)
            }
            if !output.preview.isEmpty {
                LabeledContent("Preview") {
                    Text(output.preview.joined(separator: ", "))
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
        } label: {
            Label(output.name, systemImage: "list.number")
                .font(.body.monospaced())
        }
    }
}
