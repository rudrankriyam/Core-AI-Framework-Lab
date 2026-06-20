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

        var artifacts = resourceBundleArtifact(at: outputDirectoryURL).map { [$0] } ?? []
        for case let url as URL in enumerator {
            if let resourceBundle = resourceBundleArtifact(at: url) {
                artifacts.append(resourceBundle)
            }
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
        let artifacts = discover(in: outputDirectoryURL)
        let directlyChanged = Set(
            artifacts.compactMap { artifact in
                baseline[key(for: artifact.url)] != fingerprint(for: artifact.url)
                    ? key(for: artifact.url)
                    : nil
            }
        )
        return artifacts.filter { artifact in
            let artifactKey = key(for: artifact.url)
            if directlyChanged.contains(artifactKey) {
                return true
            }
            guard artifact.kind == .resourceBundle else { return false }
            let descendantPrefix = artifactKey + "/"
            return directlyChanged.contains { $0.hasPrefix(descendantPrefix) }
        }
    }

    private static func key(for url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func fingerprint(for url: URL) -> Fingerprint {
        let values = try? url.resourceValues(
            forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        )
        guard values?.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                  at: url,
                  includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return Fingerprint(
                modificationDate: values?.contentModificationDate,
                fileSize: values?.fileSize
            )
        }

        var latestModificationDate = values?.contentModificationDate
        var totalFileSize = 0
        for case let childURL as URL in enumerator {
            let childValues = try? childURL.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey]
            )
            if let modificationDate = childValues?.contentModificationDate,
               modificationDate > (latestModificationDate ?? .distantPast) {
                latestModificationDate = modificationDate
            }
            let (updatedSize, overflow) = totalFileSize.addingReportingOverflow(
                childValues?.fileSize ?? 0
            )
            totalFileSize = overflow ? Int.max : updatedSize
        }
        return Fingerprint(
            modificationDate: latestModificationDate,
            fileSize: totalFileSize
        )
    }

    private static func resourceBundleArtifact(at url: URL) -> CoreAIConversionArtifact? {
        let metadataURL = url.appending(path: "metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let header = try? JSONDecoder().decode(CoreAIResourceBundleHeader.self, from: data),
              header.metadataVersion == "0.2" else {
            return nil
        }
        return CoreAIConversionArtifact(
            url: url,
            kind: .resourceBundle,
            resourceKind: header.kind
        )
    }
}
#endif
