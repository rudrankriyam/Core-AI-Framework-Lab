import SwiftUI

struct CoreAIFunctionBenchmarkResultsView: View {
    let reports: [CoreAIFunctionBenchmarkReport]

    var body: some View {
        Section("Benchmark History") {
            ForEach(reports) { report in
                CoreAIFunctionBenchmarkReportView(report: report)
            }
        }
    }
}
