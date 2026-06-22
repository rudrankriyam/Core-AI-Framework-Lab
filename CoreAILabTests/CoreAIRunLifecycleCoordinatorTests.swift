import Foundation
import Testing
@testable import CoreAILab

@MainActor
struct CoreAIRunLifecycleCoordinatorTests {
    @Test
    func firstModelAttemptIsColdAndTheNextIsWarm() throws {
        let firstID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let secondID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        var dates = [
            Date(timeIntervalSince1970: 10),
            Date(timeIntervalSince1970: 12.5),
            Date(timeIntervalSince1970: 20),
            Date(timeIntervalSince1970: 21)
        ]
        var identifiers = [firstID, secondID]
        var monotonicTimes = [10.0, 12.5, 20.0, 21.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() },
            makeID: { identifiers.removeFirst() }
        )
        let context = makeContext()

        let cold = coordinator.start(context: context, modelIdentity: "model.aimodel")
        #expect(cold.timingClass == .cold)
        #expect(coordinator.latestRun(for: context.experienceID)?.state == .started)
        coordinator.succeed(cold, summary: "First output")

        let warm = coordinator.start(context: context, modelIdentity: "model.aimodel")
        coordinator.succeed(warm, summary: "Second output")

        #expect(warm.timingClass == .warm)
        #expect(coordinator.history.map(\.id) == [secondID, firstID])
        #expect(coordinator.history[0].durationSeconds == 1)
        #expect(coordinator.history[1].durationSeconds == 2.5)
        #expect(coordinator.history.allSatisfy { $0.state == .succeeded })
    }

    @Test
    func selectedComparisonIsCapturedWhenTheRunStarts() {
        let comparison = CoreAIRuntimeComparisonIdentity(
            experienceID: "baseline",
            modelIdentifier: "baseline-model",
            displayName: "Baseline"
        )
        var dates = [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 2)
        ]
        var monotonicTimes = [1.0, 2.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        coordinator.registerComparisonOptions([comparison])
        coordinator.selectedComparisonIdentity = comparison

        let token = coordinator.start(
            context: makeContext(),
            modelIdentity: "candidate"
        )
        coordinator.selectedComparisonIdentity = nil
        coordinator.cancel(token)

        #expect(coordinator.history.first?.state == .canceled)
        #expect(coordinator.history.first?.selectedComparisonIdentity == comparison)
    }

    @Test
    func finishingATokenTwiceDoesNotDuplicateHistory() {
        var dates = [
            Date(timeIntervalSince1970: 1),
            Date(timeIntervalSince1970: 2)
        ]
        var monotonicTimes = [1.0, 2.0]
        let coordinator = CoreAIRunLifecycleCoordinator(
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let token = coordinator.start(
            context: makeContext(),
            modelIdentity: "candidate"
        )

        coordinator.succeed(token, summary: "Done")
        coordinator.cancel(token)

        #expect(coordinator.history.count == 1)
        #expect(coordinator.history.first?.state == .succeeded)
    }

    @Test
    func loadingAReplacementWithTheSameDisplayNameStartsANewColdSeries() {
        var dates = (1...6).map { Date(timeIntervalSince1970: Double($0)) }
        var monotonicTimes = (1...6).map(Double.init)
        let coordinator = CoreAIRunLifecycleCoordinator(
            now: { dates.removeFirst() },
            monotonicNow: { monotonicTimes.removeFirst() }
        )
        let context = makeContext()

        let first = coordinator.start(context: context, modelIdentity: "model.aimodel")
        coordinator.succeed(first, summary: "First")
        let warm = coordinator.start(context: context, modelIdentity: "model.aimodel")
        coordinator.succeed(warm, summary: "Warm")
        coordinator.modelDidLoad(context: context, modelIdentity: "model.aimodel")
        let replacement = coordinator.start(
            context: context,
            modelIdentity: "model.aimodel"
        )

        #expect(first.timingClass == .cold)
        #expect(warm.timingClass == .warm)
        #expect(replacement.timingClass == .cold)
    }

    private func makeContext() -> CoreAIRuntimeRunContext {
        .workspaceDefault(
            experienceID: "test-language",
            title: "Test Language",
            modelIdentifier: "test-model"
        )
    }
}
