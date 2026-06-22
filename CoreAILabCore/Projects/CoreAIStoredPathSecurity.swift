import Darwin
import Foundation

enum CoreAIStoredPathSecurity {
    static func contentAddressedComponents(
        for relativePath: String
    ) throws -> [String] {
        let components = relativePath.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !relativePath.hasPrefix("/"),
            components.count == 4,
            components[0] == "sha256",
            components[1].count == 2,
            components[2].count == 64,
            components[1] == String(components[2].prefix(2)),
            components[3] == "artifact" || components[3].hasPrefix("artifact."),
            components[1].allSatisfy(isLowercaseHexDigit),
            components[2].allSatisfy(isLowercaseHexDigit),
            components.allSatisfy(isSafeComponent)
        else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        return components
    }

    static func validatedURL(
        rootURL: URL,
        relativePath: String,
        requireExisting: Bool
    ) throws -> URL {
        let components = try contentAddressedComponents(for: relativePath)
        return try validatedDescendantURL(
            rootURL: rootURL,
            components: components,
            requireExisting: requireExisting
        )
    }

    static func validatedDescendantURL(
        rootURL: URL,
        components: [String],
        requireExisting: Bool
    ) throws -> URL {
        guard !components.isEmpty,
            components.allSatisfy(isSafeComponent)
        else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        try validateDirectory(at: rootURL)
        let canonicalRootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
        var candidateURL = rootURL
        var encounteredMissingComponent = false
        for (index, component) in components.enumerated() {
            candidateURL.append(path: component)
            if encounteredMissingComponent {
                continue
            }
            var metadata = stat()
            let status = candidateURL.path.withCString { path in
                lstat(path, &metadata)
            }
            if status != 0 {
                if errno == ENOENT {
                    encounteredMissingComponent = true
                    continue
                }
                throw posixError()
            }
            guard metadata.st_mode & S_IFMT != S_IFLNK else {
                throw CoreAIArtifactStoreError.invalidStoredPath
            }
            if index < components.count - 1 {
                guard metadata.st_mode & S_IFMT == S_IFDIR else {
                    throw CoreAIArtifactStoreError.invalidStoredPath
                }
            }
            let resolvedURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
            guard isContained(resolvedURL, by: canonicalRootURL) else {
                throw CoreAIArtifactStoreError.invalidStoredPath
            }
        }
        if requireExisting && encounteredMissingComponent {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        let resolvedCandidateURL = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard isContained(resolvedCandidateURL, by: canonicalRootURL) else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        return candidateURL
    }

    static func removeContentAddressedContainer(
        rootURL: URL,
        relativePath: String
    ) throws {
        let components = try contentAddressedComponents(for: relativePath)
        let containerURL = try validatedDescendantURL(
            rootURL: rootURL,
            components: Array(components.prefix(3)),
            requireExisting: false
        )
        var metadata = stat()
        let status = containerURL.path.withCString { path in
            lstat(path, &metadata)
        }
        if status != 0, errno == ENOENT { return }
        guard status == 0 else { throw posixError() }
        guard metadata.st_mode & S_IFMT != S_IFLNK else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        try removeTree(
            rootURL: rootURL,
            parentComponents: Array(components.prefix(2)),
            entryName: components[2]
        )
    }

    static func removeTree(
        rootURL: URL,
        parentComponents: [String],
        entryName: String
    ) throws {
        guard parentComponents.allSatisfy(isSafeComponent),
            isSafeComponent(entryName)
        else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
        try validateDirectory(at: rootURL)
        let rootDescriptor = try openDirectory(atPath: rootURL.path)
        defer { close(rootDescriptor) }
        var parentDescriptor = rootDescriptor
        var descriptorsToClose: [Int32] = []
        defer {
            for descriptor in descriptorsToClose.reversed() {
                close(descriptor)
            }
        }
        for component in parentComponents {
            let descriptor = try openDirectory(
                named: component,
                relativeTo: parentDescriptor
            )
            descriptorsToClose.append(descriptor)
            parentDescriptor = descriptor
        }
        try removeEntry(named: entryName, relativeTo: parentDescriptor)
    }

    private static func validateDirectory(at url: URL) throws {
        var metadata = stat()
        let status = url.path.withCString { path in
            lstat(path, &metadata)
        }
        guard status == 0,
            metadata.st_mode & S_IFMT == S_IFDIR,
            metadata.st_mode & S_IFMT != S_IFLNK
        else {
            throw CoreAIArtifactStoreError.invalidStoredPath
        }
    }

    private static func openDirectory(atPath path: String) throws -> Int32 {
        let descriptor = path.withCString { pointer in
            open(pointer, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard descriptor >= 0 else { throw posixError() }
        return descriptor
    }

    private static func openDirectory(
        named name: String,
        relativeTo parentDescriptor: Int32
    ) throws -> Int32 {
        let descriptor = name.withCString { pointer in
            openat(
                parentDescriptor,
                pointer,
                O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
            )
        }
        guard descriptor >= 0 else {
            if errno == ENOENT {
                throw CoreAIArtifactStoreError.invalidStoredPath
            }
            throw posixError()
        }
        return descriptor
    }

    private static func removeEntry(
        named name: String,
        relativeTo parentDescriptor: Int32
    ) throws {
        var metadata = stat()
        let status = name.withCString { pointer in
            fstatat(parentDescriptor, pointer, &metadata, AT_SYMLINK_NOFOLLOW)
        }
        if status != 0 {
            if errno == ENOENT { return }
            throw posixError()
        }

        if metadata.st_mode & S_IFMT == S_IFDIR {
            let childDescriptor = try openDirectory(
                named: name,
                relativeTo: parentDescriptor
            )
            guard let directory = fdopendir(childDescriptor) else {
                close(childDescriptor)
                throw posixError()
            }
            var shouldCloseDirectory = true
            defer {
                if shouldCloseDirectory {
                    closedir(directory)
                }
            }
            errno = 0
            while let entry = readdir(directory) {
                let childName = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                    pointer.withMemoryRebound(
                        to: CChar.self,
                        capacity: Int(MAXNAMLEN) + 1
                    ) {
                        String(cString: $0)
                    }
                }
                guard childName != ".", childName != ".." else { continue }
                try removeEntry(
                    named: childName,
                    relativeTo: dirfd(directory)
                )
                errno = 0
            }
            guard errno == 0 else { throw posixError() }
            let closeStatus = closedir(directory)
            shouldCloseDirectory = false
            guard closeStatus == 0 else { throw posixError() }
            let removalStatus = name.withCString { pointer in
                unlinkat(parentDescriptor, pointer, AT_REMOVEDIR)
            }
            guard removalStatus == 0 else { throw posixError() }
        } else {
            let removalStatus = name.withCString { pointer in
                unlinkat(parentDescriptor, pointer, 0)
            }
            guard removalStatus == 0 else { throw posixError() }
        }
    }

    private static func isContained(_ candidateURL: URL, by rootURL: URL) -> Bool {
        candidateURL.path == rootURL.path
            || candidateURL.path.hasPrefix(rootURL.path + "/")
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty
            && component != "."
            && component != ".."
            && !component.contains("/")
            && !component.contains("\\")
            && !component.unicodeScalars.contains {
                CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func isLowercaseHexDigit(_ character: Character) -> Bool {
        ("0"..."9").contains(character) || ("a"..."f").contains(character)
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
