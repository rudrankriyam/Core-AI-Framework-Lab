import Foundation

enum CoreAIExportPath {
    static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
    }
}
