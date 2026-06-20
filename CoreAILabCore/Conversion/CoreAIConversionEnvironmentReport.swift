import Foundation

struct CoreAIConversionEnvironmentReport: Sendable {
    let checks: [CoreAIConversionEnvironmentCheck]

    var canConvert: Bool {
        !checks.isEmpty && !checks.contains(where: \.blocksConversion)
    }
}
