import Foundation

struct CoreAIConversionRequest: Sendable {
    let modelName: String
    let command: CoreAIConversionCommand
    let outputDirectoryURL: URL
    let environmentChecks: [CoreAIConversionEnvironmentCheck]

    init(
        modelName: String,
        command: CoreAIConversionCommand,
        outputDirectoryURL: URL,
        environmentChecks: [CoreAIConversionEnvironmentCheck] = []
    ) {
        self.modelName = modelName
        self.command = command
        self.outputDirectoryURL = outputDirectoryURL
        self.environmentChecks = environmentChecks
    }
}
