#if os(macOS)
import Foundation

enum CoreAIConversionArtifactDiscoverer {
    struct Fingerprint: Equatable, Sendable {
        let modificationDate: Date?
        let fileSize: Int?
    }

    typealias Snapshot = [String: Fingerprint]

    static func discover(in outputDirectoryURL: URL) -> [CoreAIConversionArtifact] {
        guard let enumerator = FileManager.default.enumerator(
            at: outputDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var artifacts: [CoreAIConversionArtifact] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "aimodel" || url.pathExtension == "aimodelc" else {
                continue
            }
            artifacts.append(CoreAIConversionArtifact(url: url))
            enumerator.skipDescendants()
        }
        return artifacts.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func snapshot(in outputDirectoryURL: URL) -> Snapshot {
        Dictionary(
            uniqueKeysWithValues: discover(in: outputDirectoryURL).map { artifact in
                (key(for: artifact.url), fingerprint(for: artifact.url))
            }
        )
    }

    static func discoverChanges(
        in outputDirectoryURL: URL,
        comparedTo baseline: Snapshot
    ) -> [CoreAIConversionArtifact] {
        discover(in: outputDirectoryURL).filter { artifact in
            baseline[key(for: artifact.url)] != fingerprint(for: artifact.url)
        }
    }

    private static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func fingerprint(for url: URL) -> Fingerprint {
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey]
        )
        return Fingerprint(
            modificationDate: values?.contentModificationDate,
            fileSize: values?.fileSize
        )
    }
}
#endif
