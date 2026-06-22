import Darwin
import Foundation

struct CoreAIConversionJobStoreIssue: Equatable, Sendable {
    let directoryName: String
    let detail: String
}

struct CoreAIConversionJobScanResult: Equatable, Sendable {
    let jobs: [CoreAIConversionJobRecord]
    let issues: [CoreAIConversionJobStoreIssue]
}

struct CoreAIConversionJobLogReadResult: Equatable, Sendable {
    let entries: [CoreAIConversionJobLogEntry]
    let tornTailByteCount: Int
}

actor CoreAIConversionJobStore {
    private let rootURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL.standardizedFileURL
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
    }

    func createJob(
        identity: CoreAIConversionJobIdentity,
        id: UUID = UUID(),
        now: Date = .now
    ) throws -> CoreAIConversionJobRecord {
        try withStoreLock {
            let finalURL = directoryURL(for: id)
            guard !fileManager.fileExists(atPath: finalURL.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            let stagingURL = rootURL.appending(
                path: ".job-tmp-\(UUID().uuidString.lowercased())",
                directoryHint: .isDirectory
            )
            var promoted = false
            defer {
                if !promoted {
                    try? fileManager.removeItem(at: stagingURL)
                }
            }
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            try fileManager.createDirectory(
                at: stagingURL.appending(path: "checkpoints", directoryHint: .isDirectory),
                withIntermediateDirectories: false
            )
            let record = CoreAIConversionJobRecord(
                id: id,
                identity: identity,
                createdAt: now
            )
            try writeExclusive(
                try encoder.encode(record),
                to: stagingURL.appending(path: "job.json")
            )
            try syncDirectory(stagingURL)
            try fileManager.moveItem(at: stagingURL, to: finalURL)
            try syncDirectory(rootURL)
            promoted = true
            return record
        }
    }

    func job(id: UUID) throws -> CoreAIConversionJobRecord {
        try withStoreLock {
            try readJobUnlocked(id: id)
        }
    }

    func scanJobs() throws -> CoreAIConversionJobScanResult {
        try withStoreLock {
            try scanJobsUnlocked()
        }
    }

    func jobs() throws -> [CoreAIConversionJobRecord] {
        try scanJobs().jobs
    }

    @discardableResult
    func transition(
        jobID: UUID,
        to state: CoreAIConversionJobState,
        detail: String? = nil,
        now: Date = .now
    ) throws -> CoreAIConversionJobRecord {
        try withStoreLock {
            let current = try readJobUnlocked(id: jobID)
            let updated = try current.transitioning(to: state, at: now, detail: detail)
            try writeRecordUnlocked(updated)
            return updated
        }
    }

    @discardableResult
    func reconcileInterruptedJobs(now: Date = .now) throws -> [CoreAIConversionJobRecord] {
        try withStoreLock {
            var reconciled: [CoreAIConversionJobRecord] = []
            let records = try scanJobsUnlocked().jobs
            for record in records
            where record.state == .running || record.state == .cancellationRequested {
                let updated = try record.transitioning(
                    to: .interrupted,
                    at: now,
                    detail: "The app exited before the converter process reported a terminal result. Start a new attempt; Core AI Lab does not claim that the killed process resumed."
                )
                try writeRecordUnlocked(updated)
                reconciled.append(updated)
            }
            return reconciled
        }
    }

    @discardableResult
    func appendLog(
        jobID: UUID,
        kind: CoreAIConversionJobLogEntry.Kind,
        message: String,
        now: Date = .now,
        id: UUID = UUID()
    ) throws -> CoreAIConversionJobLogEntry {
        try withStoreLock {
            let record = try readJobUnlocked(id: jobID)
            let existing = try readLogUnlocked(jobID: jobID)
            if existing.result.tornTailByteCount > 0 {
                try preserveAndRemoveTornLogTail(jobID: jobID)
            }
            let lastForAttempt = existing.result.entries.last { $0.attempt == record.attempt }
            guard existing.result.entries.allSatisfy({ $0.attempt <= record.attempt }) else {
                throw CoreAIConversionJobStoreError.corruptLog(jobID)
            }
            let entry = CoreAIConversionJobLogEntry(
                id: id,
                attempt: record.attempt,
                sequence: (lastForAttempt?.sequence ?? 0) + 1,
                createdAt: now,
                kind: kind,
                message: message
            )
            var data = try encoder.encode(entry)
            data.append(0x0A)
            try append(data, to: logURL(for: jobID))
            return entry
        }
    }

    func readLogs(jobID: UUID) throws -> CoreAIConversionJobLogReadResult {
        try withStoreLock {
            _ = try readJobUnlocked(id: jobID)
            return try readLogUnlocked(jobID: jobID).result
        }
    }

    func logs(jobID: UUID) throws -> [CoreAIConversionJobLogEntry] {
        try readLogs(jobID: jobID).entries
    }

    func saveCheckpoint(jobID: UUID, checkpoint: CoreAIConversionCheckpoint) throws {
        try withStoreLock {
            let record = try readJobUnlocked(id: jobID)
            guard record.fingerprint == checkpoint.fingerprint,
                  checkpoint.jobID == jobID,
                  checkpoint.artifactRootPath == record.identity.request.outputDirectoryPath else {
                throw CoreAIConversionJobStoreError.checkpointFingerprintMismatch
            }
            let directory = try openCheckpointsDirectory(jobID: jobID)
            defer { close(directory) }
            try writeAtomically(
                try encoder.encode(checkpoint),
                fileName: "\(checkpoint.gate).json",
                directoryDescriptor: directory
            )
        }
    }

    func checkpoint(jobID: UUID, gate: String) throws -> CoreAIConversionCheckpoint? {
        try withStoreLock {
            let record = try readJobUnlocked(id: jobID)
            try validateGate(gate)
            let directory = try openCheckpointsDirectory(jobID: jobID)
            defer { close(directory) }
            let fileName = "\(gate).json"
            guard faccessat(directory, fileName, F_OK, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno == ENOENT { return nil }
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
            let checkpoint = try decoder.decode(
                CoreAIConversionCheckpoint.self,
                from: readNoFollow(fileName: fileName, directoryDescriptor: directory)
            )
            guard checkpoint.gate == gate,
                  checkpoint.fingerprint == record.fingerprint,
                  checkpoint.jobID == record.id,
                  checkpoint.artifactRootPath == record.identity.request.outputDirectoryPath else {
                throw CoreAIConversionJobStoreError.checkpointFingerprintMismatch
            }
            return checkpoint
        }
    }

    func checkpointReuseDecision(
        jobID: UUID,
        gate: String,
        currentIdentity: CoreAIConversionJobIdentity
    ) throws -> CoreAIConversionCheckpointReuseDecision? {
        guard let checkpoint = try checkpoint(jobID: jobID, gate: gate) else { return nil }
        let fingerprint = currentIdentity.fingerprint
        guard checkpoint.fingerprint.requestSHA256 == fingerprint.requestSHA256 else {
            return .requestChanged
        }
        guard checkpoint.fingerprint.environmentSHA256 == fingerprint.environmentSHA256 else {
            return .environmentChanged
        }
        let verifier = CoreAIConversionCheckpointArtifactVerifier()
        let verified = try checkpoint.artifacts.map { artifact in
            try verifier.evidence(
                for: artifact,
                under: URL(filePath: checkpoint.artifactRootPath)
            )
        }
        return CoreAIConversionCheckpointReuseEvaluator.evaluate(
            checkpoint,
            expectedGate: gate,
            currentFingerprint: fingerprint,
            verifiedArtifacts: verified
        )
    }

    private func withStoreLock<T>(_ operation: () throws -> T) throws -> T {
        try prepareRoot()
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private func prepareRoot() throws {
        if fileManager.fileExists(atPath: rootURL.path) {
            let values = try rootURL.resourceValues(
                forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
            )
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CoreAIConversionJobStoreError.unsafeStoreItem(rootURL.lastPathComponent)
            }
        } else {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        }
    }

    private func scanJobsUnlocked() throws -> CoreAIConversionJobScanResult {
        let urls = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )
        var records: [CoreAIConversionJobRecord] = []
        var issues: [CoreAIConversionJobStoreIssue] = []
        for url in urls {
            guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
            do {
                records.append(try readJobUnlocked(id: id))
            } catch {
                issues.append(
                    CoreAIConversionJobStoreIssue(
                        directoryName: url.lastPathComponent,
                        detail: error.localizedDescription
                    )
                )
            }
        }
        records.sort { first, second in
            if first.createdAt != second.createdAt { return first.createdAt < second.createdAt }
            return first.id.uuidString < second.id.uuidString
        }
        issues.sort { $0.directoryName < $1.directoryName }
        return CoreAIConversionJobScanResult(jobs: records, issues: issues)
    }

    private func readJobUnlocked(id: UUID) throws -> CoreAIConversionJobRecord {
        try validateJobDirectory(id: id)
        let url = recordURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CoreAIConversionJobStoreError.jobNotFound(id)
        }
        let record = try decoder.decode(
            CoreAIConversionJobRecord.self,
            from: readNoFollow(url)
        )
        guard record.id == id else {
            throw CoreAIConversionJobStoreError.corruptRecord
        }
        return record
    }

    private func validateJobDirectory(id: UUID) throws {
        let url = directoryURL(for: id)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw CoreAIConversionJobStoreError.unsafeStoreItem(url.lastPathComponent)
        }
    }

    private func writeRecordUnlocked(_ record: CoreAIConversionJobRecord) throws {
        try validateJobDirectory(id: record.id)
        try writeAtomically(try encoder.encode(record), to: recordURL(for: record.id))
    }

    private func readLogUnlocked(
        jobID: UUID
    ) throws -> (result: CoreAIConversionJobLogReadResult, completePrefix: Data, tornTail: Data) {
        let url = logURL(for: jobID)
        guard fileManager.fileExists(atPath: url.path) else {
            return (CoreAIConversionJobLogReadResult(entries: [], tornTailByteCount: 0), Data(), Data())
        }
        let data = try readNoFollow(url)
        let completeEnd: Data.Index
        if data.isEmpty {
            completeEnd = data.startIndex
        } else if data.last == 0x0A {
            completeEnd = data.endIndex
        } else if let newline = data.lastIndex(of: 0x0A) {
            completeEnd = data.index(after: newline)
        } else {
            completeEnd = data.startIndex
        }
        let prefix = Data(data[..<completeEnd])
        let tail = Data(data[completeEnd...])
        var entries: [CoreAIConversionJobLogEntry] = []
        for line in prefix.split(separator: 0x0A) {
            let entry: CoreAIConversionJobLogEntry
            do {
                entry = try decoder.decode(CoreAIConversionJobLogEntry.self, from: Data(line))
            } catch {
                throw CoreAIConversionJobStoreError.corruptLog(jobID)
            }
            guard entry.schemaVersion == CoreAIConversionJobLogEntry.currentSchemaVersion,
                  entry.attempt >= 1,
                  entry.sequence >= 1 else {
                throw CoreAIConversionJobStoreError.corruptLog(jobID)
            }
            if let previous = entries.last {
                let continuesAttempt = entry.attempt == previous.attempt
                    && entry.sequence == previous.sequence + 1
                let startsAttempt = entry.attempt > previous.attempt && entry.sequence == 1
                guard continuesAttempt || startsAttempt else {
                    throw CoreAIConversionJobStoreError.corruptLog(jobID)
                }
            } else if entry.sequence != 1 {
                throw CoreAIConversionJobStoreError.corruptLog(jobID)
            }
            entries.append(entry)
        }
        return (
            CoreAIConversionJobLogReadResult(
                entries: entries,
                tornTailByteCount: tail.count
            ),
            prefix,
            tail
        )
    }

    private func preserveAndRemoveTornLogTail(jobID: UUID) throws {
        let log = try readLogUnlocked(jobID: jobID)
        guard !log.tornTail.isEmpty else { return }
        let diagnosticURL = directoryURL(for: jobID).appending(
            path: "events-torn-\(UUID().uuidString.lowercased()).bin"
        )
        try writeExclusive(log.tornTail, to: diagnosticURL)
        try syncDirectory(directoryURL(for: jobID))
        try truncate(logURL(for: jobID), to: log.completePrefix.count)
    }

    private func validateGate(_ gate: String) throws {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
        )
        guard !gate.isEmpty,
              gate.utf8.count <= 80,
              gate.unicodeScalars.allSatisfy(allowed.contains) else {
            throw CoreAIConversionJobStoreError.invalidCheckpointGate(gate)
        }
    }

    private func readNoFollow(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            throw CoreAIConversionJobStoreError.unsafeStoreItem(url.lastPathComponent)
        }
        return try handle.readToEnd() ?? Data()
    }

    private func writeExclusive(_ data: Data, to url: URL) throws {
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        try writeAll(data, descriptor: descriptor)
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    private func append(_ data: Data, to url: URL) throws {
        let descriptor = open(
            url.path,
            O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            throw CoreAIConversionJobStoreError.unsafeStoreItem(url.lastPathComponent)
        }
        try writeAll(data, descriptor: descriptor)
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    private func truncate(_ url: URL, to byteCount: Int) throws {
        let descriptor = open(url.path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard ftruncate(descriptor, off_t(byteCount)) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    private func openCheckpointsDirectory(jobID: UUID) throws -> Int32 {
        let jobDescriptor = open(
            directoryURL(for: jobID).path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard jobDescriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(jobDescriptor) }
        let descriptor = openat(
            jobDescriptor,
            "checkpoints",
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw CoreAIConversionJobStoreError.unsafeStoreItem("checkpoints")
        }
        return descriptor
    }

    private func readNoFollow(fileName: String, directoryDescriptor: Int32) throws -> Data {
        let descriptor = openat(
            directoryDescriptor,
            fileName,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            throw CoreAIConversionJobStoreError.unsafeStoreItem(fileName)
        }
        return try handle.readToEnd() ?? Data()
    }

    private func writeAtomically(
        _ data: Data,
        fileName: String,
        directoryDescriptor: Int32
    ) throws {
        let temporaryName = ".\(fileName).tmp-\(UUID().uuidString.lowercased())"
        var moved = false
        defer {
            if !moved { unlinkat(directoryDescriptor, temporaryName, 0) }
        }
        let descriptor = openat(
            directoryDescriptor,
            temporaryName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        do {
            defer { close(descriptor) }
            try writeAll(data, descriptor: descriptor)
            guard fsync(descriptor) == 0 else {
                throw POSIXError(.init(rawValue: errno) ?? .EIO)
            }
        }
        guard renameat(directoryDescriptor, temporaryName, directoryDescriptor, fileName) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        guard fsync(directoryDescriptor) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        moved = true
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        let temporaryURL = url.deletingLastPathComponent().appending(
            path: ".\(url.lastPathComponent).tmp-\(UUID().uuidString.lowercased())"
        )
        var moved = false
        defer {
            if !moved { try? fileManager.removeItem(at: temporaryURL) }
        }
        try writeExclusive(data, to: temporaryURL)
        guard rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(.init(rawValue: errno) ?? .EIO)
        }
        try syncDirectory(url.deletingLastPathComponent())
        moved = true
    }

    private func writeAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw POSIXError(.init(rawValue: errno) ?? .EIO)
                }
                offset += count
            }
        }
    }

    private func syncDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
    }

    private var lockURL: URL { rootURL.appending(path: ".store.lock") }

    private func directoryURL(for id: UUID) -> URL {
        rootURL.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }

    private func recordURL(for id: UUID) -> URL {
        directoryURL(for: id).appending(path: "job.json")
    }

    private func logURL(for id: UUID) -> URL {
        directoryURL(for: id).appending(path: "events.jsonl")
    }

}
