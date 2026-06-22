import Foundation

struct CoreAIBenchmarkEvidenceCodec: Sendable {
    func encode(_ document: CoreAIBenchmarkEvidenceDocument) throws -> Data {
        try document.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        return try encoder.encode(document)
    }

    func decode(_ data: Data) throws -> CoreAIBenchmarkEvidenceDocument {
        let document = try JSONDecoder().decode(
            CoreAIBenchmarkEvidenceDocument.self,
            from: data
        )
        try document.validate()
        return document
    }
}
