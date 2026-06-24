import SwiftUI

struct CoreAIFunctionBenchmarkResultsView: View {
    let reports: [CoreAIFunctionBenchmarkReport]
    let exportEvidence: (CoreAIFunctionBenchmarkReport) -> Void

    var body: some View {
        Section {
            ForEach(reports) { report in
                CoreAIFunctionBenchmarkReportView(
                    report: report,
                    exportEvidence: exportEvidence
                )
            }
        } header: {
            Label("Benchmark History", systemImage: "clock.arrow.circlepath")
        }
    }
}
