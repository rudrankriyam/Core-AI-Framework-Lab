import Foundation
import Observation

@MainActor
@Observable
final class CoreAIRunLifecycleCoordinator {
    private(set) var activeRuns: [CoreAIRuntimeRunSummary] = []
    private(set) var history: [CoreAIRuntimeRunSummary] = []
    private(set) var comparisonOptions: [CoreAIRuntimeComparisonIdentity] = []
    private(set) var persistenceMessage: String?
    var selectedComparisonIdentity: CoreAIRuntimeComparisonIdentity?

    @ObservationIgnored
    private var persistence: (any CoreAIRunPersisting)?
    @ObservationIgnored
    private var persistenceRuns: [UUID: CoreAIRuntimePersistenceRun] = [:]
    @ObservationIgnored
    private var successfulTimingScopes = Set<String>()
    @ObservationIgnored
    private let now: @MainActor () -> Date
    @ObservationIgnored
    private let monotonicNow: @MainActor () -> TimeInterval
    @ObservationIgnored
    private let makeID: @MainActor () -> UUID

    init(
        persistence: (any CoreAIRunPersisting)? = nil,
        now: @escaping @MainActor () -> Date = { .now },
        monotonicNow: @escaping @MainActor () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        },
        makeID: @escaping @MainActor () -> UUID = { UUID() }
    ) {
        self.persistence = persistence
        self.now = now
        self.monotonicNow = monotonicNow
        self.makeID = makeID
    }

    var hasActiveRuns: Bool {
        !activeRuns.isEmpty
    }

    var hasPendingPersistenceWrites: Bool {
        persistenceRuns.values.contains {
            $0.persistentRunID == nil || $0.completedSummary != nil
        }
    }

    func configurePersistence(_ persistence: (any CoreAIRunPersisting)?) {
        self.persistence = persistence
        if !hasPendingPersistenceWrites {
            persistenceMessage = nil
        }
    }

    func registerComparisonOptions(_ options: [CoreAIRuntimeComparisonIdentity]) {
        comparisonOptions = Array(Set(options)).sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
        if let selectedComparisonIdentity,
           !comparisonOptions.contains(selectedComparisonIdentity) {
            self.selectedComparisonIdentity = nil
        }
    }

    func modelDidLoad(
        context: CoreAIRuntimeRunContext,
        modelIdentity: String
    ) {
        successfulTimingScopes.remove(
            "\(context.experienceID)|\(modelIdentity)"
        )
    }

    @discardableResult
    func recoverInterruptedPersistence() -> Int {
        guard !hasActiveRuns, let persistence else { return 0 }
        do {
            let recoveredCount = try persistence.recoverInterruptedRuns(
                endedAt: now()
            )
            if recoveredCount > 0 {
                let noun = recoveredCount == 1 ? "run" : "runs"
                persistenceMessage = "Marked \(recoveredCount) interrupted project \(noun) as failed."
            } else if !hasPendingPersistenceWrites {
                persistenceMessage = nil
            }
            return recoveredCount
        } catch {
            persistenceMessage = "Interrupted run recovery failed: \(error.localizedDescription)"
            return 0
        }
    }

    @discardableResult
    func start(
        context: CoreAIRuntimeRunContext,
        modelIdentity: String
    ) -> CoreAIRuntimeRunToken {
        registerComparisonOption(context.comparisonIdentity)
        let startedAt = now()
        let scope = "\(context.experienceID)|\(modelIdentity)"
        let timingClass: CoreAIRuntimeTimingClass = successfulTimingScopes.contains(scope)
            ? .warm
            : .cold
        let identifier = makeID()
        let selectedComparison = selectedComparisonIdentity
        let runStart = CoreAIRuntimeRunStart(
            id: identifier,
            context: context,
            modelIdentity: modelIdentity,
            timingClass: timingClass,
            selectedComparisonIdentity: selectedComparison,
            startedAt: startedAt
        )

        if let persistence {
            persistenceRuns[identifier] = CoreAIRuntimePersistenceRun(
                persistence: persistence,
                start: runStart,
                persistentRunID: nil,
                completedSummary: nil
            )
            persistRun(identifier: identifier)
        }

        // Project bookkeeping is intentionally excluded from runtime timing.
        let token = CoreAIRuntimeRunToken(
            id: identifier,
            context: context,
            modelIdentity: modelIdentity,
            timingClass: timingClass,
            selectedComparisonIdentity: selectedComparison,
            startedAt: startedAt,
            startedMonotonicSeconds: monotonicNow()
        )
        activeRuns.append(
            CoreAIRuntimeRunSummary(
                id: token.id,
                context: context,
                modelIdentity: modelIdentity,
                state: .started,
                timingClass: timingClass,
                selectedComparisonIdentity: selectedComparison,
                startedAt: startedAt,
                endedAt: nil,
                durationSeconds: nil,
                summary: "Running \(context.experienceTitle)."
            )
        )
        return token
    }

    func succeed(_ token: CoreAIRuntimeRunToken, summary: String) {
        finish(token, state: .succeeded, summary: summary)
    }

    func fail(_ token: CoreAIRuntimeRunToken, error: any Error) {
        finish(token, state: .failed, summary: error.localizedDescription)
    }

    func cancel(_ token: CoreAIRuntimeRunToken, summary: String = "Canceled by the user.") {
        finish(token, state: .canceled, summary: summary)
    }

    func latestRun(for experienceID: String) -> CoreAIRuntimeRunSummary? {
        activeRuns.last { $0.context.experienceID == experienceID }
            ?? history.first { $0.context.experienceID == experienceID }
    }

    func retryPendingPersistence() {
        let identifiers = persistenceRuns.compactMap { identifier, run in
            run.persistentRunID == nil || run.completedSummary != nil
                ? identifier
                : nil
        }
        for identifier in identifiers {
            persistRun(identifier: identifier)
        }
    }

    private func finish(
        _ token: CoreAIRuntimeRunToken,
        state: CoreAIRuntimeLifecycleState,
        summary: String
    ) {
        guard let index = activeRuns.firstIndex(where: { $0.id == token.id }) else {
            return
        }
        activeRuns.remove(at: index)
        let endedAt = now()
        let endedMonotonicSeconds = monotonicNow()
        let completed = CoreAIRuntimeRunSummary(
            id: token.id,
            context: token.context,
            modelIdentity: token.modelIdentity,
            state: state,
            timingClass: token.timingClass,
            selectedComparisonIdentity: token.selectedComparisonIdentity,
            startedAt: token.startedAt,
            endedAt: endedAt,
            durationSeconds: max(
                0,
                endedMonotonicSeconds - token.startedMonotonicSeconds
            ),
            summary: summary
        )
        history.insert(completed, at: 0)
        if state == .succeeded {
            successfulTimingScopes.insert(
                "\(token.context.experienceID)|\(token.modelIdentity)"
            )
        }

        if var persistenceRun = persistenceRuns[token.id] {
            persistenceRun.completedSummary = completed
            persistenceRuns[token.id] = persistenceRun
            persistRun(identifier: token.id)
        }
    }

    private func persistRun(identifier: UUID) {
        guard var persistenceRun = persistenceRuns[identifier] else { return }

        if persistenceRun.persistentRunID == nil {
            do {
                persistenceRun.persistentRunID = try persistenceRun.persistence.startRun(
                    start: persistenceRun.start
                )
                persistenceRuns[identifier] = persistenceRun
            } catch {
                persistenceMessage = "Run recording could not start: \(error.localizedDescription) Retry when project storage is available."
                return
            }
        }

        guard let persistentRunID = persistenceRun.persistentRunID,
              let completed = persistenceRun.completedSummary else {
            persistenceMessage = pendingPersistenceMessage
            return
        }

        do {
            try persistenceRun.persistence.finishRun(
                persistentRunID: persistentRunID,
                summary: completed
            )
            persistenceRuns.removeValue(forKey: identifier)
            persistenceMessage = pendingPersistenceMessage
        } catch {
            persistenceMessage = "Run recording could not finish: \(error.localizedDescription) Retry when project storage is available."
        }
    }

    private var pendingPersistenceMessage: String? {
        hasPendingPersistenceWrites
            ? "Some runs still need to be recorded."
            : nil
    }

    private func registerComparisonOption(_ option: CoreAIRuntimeComparisonIdentity) {
        guard !comparisonOptions.contains(option) else { return }
        comparisonOptions.append(option)
        comparisonOptions.sort {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
