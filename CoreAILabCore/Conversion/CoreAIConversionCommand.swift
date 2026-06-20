import Foundation

struct CoreAIConversionCommand: Equatable, Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectoryURL: URL

    var displayString: String {
        Self.displayString(
            executableName: executableURL.path,
            arguments: arguments
        )
    }

    static func displayString(
        executableName: String,
        arguments: [String]
    ) -> String {
        ([executableName] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        let safeCharacters = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._/:=@+")
        )
        guard value.unicodeScalars.allSatisfy(safeCharacters.contains) else {
            return "'\(value.replacing("'", with: "'\\''"))'"
        }
        return value
    }
}
