import Foundation
import Observation

@MainActor
@Observable
final class CoreAIDeviceLabWorkspaceModel {
    typealias EvidenceLoader = @Sendable (
        URL
    ) async throws -> CoreAIDeviceTrialEvidence

    var preferredComputeUnit = CoreAIComputeUnitPreference.automatic
    var expectsFrequentReshapes = false
    var declaresContextWindow = false
    var requestedContextTokens = 2_048
    var maximumContextTokens = 4_096
    var batchSize = 1
    var tokenWidth = 4
    var valueWidth = 4
    var usesDynamicSequenceDimension = false
    var modelSizeMiB = 512
    var installedModelSizeMiB = 640
    var appDownloadBudgetMiB = 256
    var availableStorageMiB = 4_096
    var temporaryWorkingMiB = 512
    var modelDeliveryMode = CoreAIAssetDeliveryMode.onDemand
    private(set) var importedEvidence: CoreAIDeviceTrialEvidence?
    private(set) var importErrorMessage: String?
    private(set) var isImportingEvidence = false
    let evidenceExpectation: CoreAIDeviceEvidenceExpectation
    @ObservationIgnored private let evidenceLoader: EvidenceLoader
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = UUID()

    init(
        evidenceExpectation: CoreAIDeviceEvidenceExpectation =
            CoreAIDeviceHarnessFixtureContract.expectation,
        evidenceLoader: @escaping EvidenceLoader = { url in
            try await CoreAIDeviceEvidenceImporter.load(from: url)
        }
    ) {
        self.evidenceExpectation = evidenceExpectation
        self.evidenceLoader = evidenceLoader
    }

    var shapeRequest: CoreAIDeviceShapeAuthoringRequest {
        CoreAIDeviceShapeAuthoringRequest(
            requestedContextTokens: declaresContextWindow
                ? requestedContextTokens
                : nil,
            maximumContextTokens: declaresContextWindow
                ? maximumContextTokens
                : nil,
            expectsFrequentReshapes: expectsFrequentReshapes,
            shapes: [
                CoreAIDeviceShapeDefinition(
                    id: "tokens",
                    dimensions: [
                        batchSize,
                        usesDynamicSequenceDimension ? nil : tokenWidth,
                    ]
                ),
                CoreAIDeviceShapeDefinition(
                    id: "values",
                    dimensions: [
                        batchSize,
                        usesDynamicSequenceDimension ? nil : valueWidth,
                    ]
                ),
            ]
        )
    }

    var diagnostics: [CoreAIDeviceDiagnostic] {
        CoreAIDeviceAuthoringDiagnostics.evaluate(
            shapeRequest: shapeRequest,
            preferredComputeUnit: preferredComputeUnit,
            expectation: evidenceExpectation,
            evidence: importedEvidence
        )
    }

    var storagePlan: CoreAIDeviceStoragePlan? {
        switch storagePlanResult {
        case .success(let plan):
            plan
        case .failure:
            nil
        }
    }

    var storagePlanErrorMessage: String? {
        switch storagePlanResult {
        case .success:
            nil
        case .failure(let error):
            error.localizedDescription
        }
    }

    var connectedProfile: CoreAIConnectedDeviceTargetProfile? {
        guard let evidence = importedEvidence,
              evidenceExpectation.matches(evidence) else { return nil }
        return CoreAIConnectedDeviceTargetProfile(
            id: evidence.configuration.identifier,
            displayName: "\(evidence.device.modelName) trial",
            device: evidence.device,
            minimumOSVersion: evidence.device.operatingSystemVersion,
            preferredComputeUnit: evidence.configuration.preferredComputeUnit,
            expectsFrequentReshapes: evidence.configuration.expectsFrequentReshapes,
            contextTokenLimit: evidence.configuration.contextTokens,
            staticInputShapes: evidence.configuration.staticInputShapes
        )
    }

    func computeUnitTitle(_ preference: CoreAIComputeUnitPreference) -> String {
        switch preference {
        case .automatic:
            "Automatic"
        case .cpu:
            "CPU"
        case .gpu:
            "Prefer GPU"
        case .neuralEngine:
            "Prefer Neural Engine"
        }
    }

    func importEvidence(from url: URL) {
        importTask?.cancel()
        let generation = UUID()
        importGeneration = generation
        isImportingEvidence = true
        importErrorMessage = nil
        importedEvidence = nil
        let loader = evidenceLoader
        importTask = Task { [weak self] in
            do {
                let evidence = try await loader(url)
                try evidence.validate()
                guard let self, self.importGeneration == generation else {
                    return
                }
                self.importedEvidence = evidence
                self.importErrorMessage = nil
                self.isImportingEvidence = false
            } catch is CancellationError {
                guard let self, self.importGeneration == generation else {
                    return
                }
                self.isImportingEvidence = false
            } catch {
                guard let self, self.importGeneration == generation else {
                    return
                }
                self.importedEvidence = nil
                self.importErrorMessage = error.localizedDescription
                self.isImportingEvidence = false
            }
        }
    }

    func reportImportFailure(_ error: Error) {
        importTask?.cancel()
        importGeneration = UUID()
        importedEvidence = nil
        importErrorMessage = error.localizedDescription
        isImportingEvidence = false
    }

    private var storagePlanResult: Result<CoreAIDeviceStoragePlan, Error> {
        Result {
            try CoreAIDeviceStoragePlanner.plan(request: storageRequest)
        }
    }

    private var storageRequest: CoreAIDeviceStoragePlanRequest {
        get throws {
            CoreAIDeviceStoragePlanRequest(
                slices: [
                    CoreAIAssetDeliverySlice(
                        id: "runtime-support",
                        displayName: "Runtime support",
                        downloadByteCount: try bytes(mebibytes: 16),
                        installedByteCount: try bytes(mebibytes: 16),
                        deliveryMode: .appDownload
                    ),
                    CoreAIAssetDeliverySlice(
                        id: "model-assets",
                        displayName: "Model assets",
                        downloadByteCount: try bytes(mebibytes: modelSizeMiB),
                        installedByteCount: try bytes(
                            mebibytes: installedModelSizeMiB
                        ),
                        deliveryMode: modelDeliveryMode
                    ),
                ],
                appDownloadBudgetBytes: try bytes(
                    mebibytes: appDownloadBudgetMiB
                ),
                availableDeviceBytes: try bytes(
                    mebibytes: availableStorageMiB
                ),
                temporaryWorkingBytes: try bytes(
                    mebibytes: temporaryWorkingMiB
                )
            )
        }
    }

    private func bytes(mebibytes: Int) throws -> UInt64 {
        guard mebibytes >= 0, let value = UInt64(exactly: mebibytes) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "deviceLab.storage",
                reason: "storage values must be zero or greater"
            )
        }
        let product = value.multipliedReportingOverflow(by: 1_048_576)
        guard !product.overflow else {
            throw CoreAIDeviceEvidenceError.arithmeticOverflow(
                path: "deviceLab.storage"
            )
        }
        return product.partialValue
    }
}
