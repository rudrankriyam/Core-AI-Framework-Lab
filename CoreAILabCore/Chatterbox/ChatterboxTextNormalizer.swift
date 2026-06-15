import Foundation

enum ChatterboxTextNormalizer {
    static func normalize(_ source: String) -> String {
        var text = source
        if text.isEmpty {
            return "You need to add some text for me to talk."
        }

        if let first = text.first, first.isLowercase {
            text.replaceSubrange(
                text.startIndex...text.startIndex,
                with: String(first).uppercased()
            )
        }

        text = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let replacements = [
            ("…", ", "),
            (":", ","),
            ("—", "-"),
            ("–", "-"),
            (" ,", ","),
            ("“", "\""),
            ("”", "\""),
            ("‘", "'"),
            ("’", "'"),
        ]
        for (source, replacement) in replacements {
            text = text.replacingOccurrences(of: source, with: replacement)
        }

        text = text.trimmingCharacters(in: .whitespaces)
        if ![".", "!", "?", "-", ","].contains(where: text.hasSuffix) {
            text.append(".")
        }
        return text
    }
}
