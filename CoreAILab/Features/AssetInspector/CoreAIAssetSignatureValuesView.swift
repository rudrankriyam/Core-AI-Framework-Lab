import SwiftUI

struct CoreAIAssetSignatureValuesView: View {
    let title: String
    let values: [CoreAIAssetValueSignature]

    var body: some View {
        if !values.isEmpty {
            LabeledContent(title) {
                VStack(alignment: .trailing, spacing: 4) {
                    ForEach(values) { value in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(value.name)
                                .font(.body.monospaced())
                            Text(value.typeName)
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
