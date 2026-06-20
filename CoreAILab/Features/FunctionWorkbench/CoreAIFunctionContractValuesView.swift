import SwiftUI

struct CoreAIFunctionContractValuesView: View {
    let title: String
    let values: [CoreAIFunctionValueContract]

    var body: some View {
        if !values.isEmpty {
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(values) { value in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(value.name)
                                .font(.body.monospaced())
                            Text(value.kind.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}
