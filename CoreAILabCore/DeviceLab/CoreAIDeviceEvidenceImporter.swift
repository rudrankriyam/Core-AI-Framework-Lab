import Foundation

enum CoreAIDeviceEvidenceImporter {
    static let maximumByteCount: UInt64 = 1_048_576

    @concurrent
    static func load(from url: URL) async throws -> CoreAIDeviceTrialEvidence {
        try Task.checkCancellation()
        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw CoreAIDeviceEvidenceImportError.notARegularFile
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let byteCount = try handle.seekToEnd()
        guard byteCount > 0 else {
            throw CoreAIDeviceEvidenceImportError.emptyFile
        }
        guard byteCount <= Self.maximumByteCount else {
            throw CoreAIDeviceEvidenceImportError.fileTooLarge(
                found: byteCount,
                maximum: Self.maximumByteCount
            )
        }
        try handle.seek(toOffset: 0)
        let maximumReadCount = Int(Self.maximumByteCount) + 1
        let data = try handle.read(upToCount: maximumReadCount) ?? Data()
        guard !data.isEmpty else {
            throw CoreAIDeviceEvidenceImportError.emptyFile
        }
        guard UInt64(data.count) <= Self.maximumByteCount else {
            throw CoreAIDeviceEvidenceImportError.fileTooLarge(
                found: UInt64(data.count),
                maximum: Self.maximumByteCount
            )
        }
        try Task.checkCancellation()
        let evidence = try JSONDecoder().decode(
            CoreAIDeviceTrialEvidence.self,
            from: data
        )
        try evidence.validate()
        return evidence
    }
}
