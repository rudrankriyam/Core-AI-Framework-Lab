import SwiftUI

struct CoreAIBenchmarkDurationRow: View {
    let title: String
    let duration: Duration

    var body: some View {
        LabeledContent(title) {
            Text(
                "\(duration.coreAIMilliseconds, format: .number.precision(.fractionLength(2))) ms"
            )
        }
    }
}
