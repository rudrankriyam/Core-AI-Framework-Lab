import SwiftUI

struct CoreAIFunctionBenchmarkResultsView: View {
    let reports: [CoreAIFunctionBenchmarkReport]
    let exportEvidence: (CoreAIFunctionBenchmarkReport) -> Void

    var body: some View {
        Section("Benchmark History") {
            ForEach(reports) { report in
                CoreAIFunctionBenchmarkReportView(
                    report: report,
                    exportEvidence: exportEvidence
                )
            }
        }
    }
}
