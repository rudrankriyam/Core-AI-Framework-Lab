import Foundation

struct CoreAIDeviceTrialEvidence: Codable, Equatable, Identifiable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: String
    let runMode: CoreAIDeviceRunMode
    let capturedAt: String
    let device: CoreAIDeviceFacts
    let artifact: CoreAIDeviceArtifactIdentity
    let configuration: CoreAIDeviceConfigurationIdentity
    let specialization: CoreAIDeviceTrialOutcome
    let inference: CoreAIDeviceTrialOutcome
    let latency: CoreAIDeviceLatencyEvidence
    let memory: CoreAIDeviceMemoryEvidence
    let thermal: CoreAIDeviceThermalEvidence
    let energy: CoreAIDeviceEnergyEvidence
    let placement: CoreAIDevicePlacementEvidence
    let neuralEngineCompatibilityChecks: [CoreAINECompatibilityCheck]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        id: String,
        runMode: CoreAIDeviceRunMode,
        capturedAt: String,
        device: CoreAIDeviceFacts,
        artifact: CoreAIDeviceArtifactIdentity,
        configuration: CoreAIDeviceConfigurationIdentity,
        specialization: CoreAIDeviceTrialOutcome,
        inference: CoreAIDeviceTrialOutcome,
        latency: CoreAIDeviceLatencyEvidence,
        memory: CoreAIDeviceMemoryEvidence,
        thermal: CoreAIDeviceThermalEvidence,
        energy: CoreAIDeviceEnergyEvidence,
        placement: CoreAIDevicePlacementEvidence,
        neuralEngineCompatibilityChecks: [CoreAINECompatibilityCheck]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.runMode = runMode
        self.capturedAt = capturedAt
        self.device = device
        self.artifact = artifact
        self.configuration = configuration
        self.specialization = specialization
        self.inference = inference
        self.latency = latency
        self.memory = memory
        self.thermal = thermal
        self.energy = energy
        self.placement = placement
        self.neuralEngineCompatibilityChecks = neuralEngineCompatibilityChecks
    }

    func validate(path: String = "deviceTrial") throws {
        try CoreAIManifestValidator.requireCurrentSchemaVersion(
            schemaVersion,
            supported: Self.currentSchemaVersion,
            path: "\(path).schemaVersion"
        )
        try CoreAIManifestValidator.requireNonempty(id, path: "\(path).id")
        try validateTimestamp(path: "\(path).capturedAt")
        try device.validate(path: "\(path).device")
        try artifact.validate(path: "\(path).artifact")
        try configuration.validate(path: "\(path).configuration")
        try specialization.validate(path: "\(path).specialization")
        try inference.validate(path: "\(path).inference")
        try latency.validate(path: "\(path).latency")
        try memory.validate(path: "\(path).memory")
        try thermal.validate(path: "\(path).thermal")
        try energy.validate(path: "\(path).energy")
        try placement.validate(path: "\(path).placement")
        try CoreAIManifestValidator.requireUniqueIdentifiers(
            neuralEngineCompatibilityChecks,
            path: "\(path).neuralEngineCompatibilityChecks",
            identifier: { $0.category.rawValue }
        )
        guard Set(neuralEngineCompatibilityChecks.map(\.category))
                == Set(CoreAINECompatibilityCategory.allCases) else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: "\(path).neuralEngineCompatibilityChecks",
                reason: "precision, layout, projection, and operation checks must all be explicit"
            )
        }
        for (index, check) in neuralEngineCompatibilityChecks.enumerated() {
            try check.validate(path: "\(path).neuralEngineCompatibilityChecks[\(index)]")
        }

        if runMode == .dryRun {
            guard specialization.status == .notRun,
                  inference.status == .notRun,
                  latency.availability == .unavailable,
                  memory.availability == .unavailable,
                  thermal == .unavailable,
                  energy.availability == .unavailable,
                  placement.availability == .unavailable,
                  neuralEngineCompatibilityChecks.allSatisfy({
                      $0.result == .notEvaluated
                  }) else {
                throw CoreAIDeviceEvidenceError.invalidValue(
                    path: path,
                    reason: "a dry run must not claim execution or observed runtime metrics"
                )
            }
        }
    }

    private func validateTimestamp(path: String) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFractions = ISO8601DateFormatter()
        guard formatter.date(from: capturedAt) != nil
                || withoutFractions.date(from: capturedAt) != nil else {
            throw CoreAIDeviceEvidenceError.invalidValue(
                path: path,
                reason: "expected an ISO 8601 timestamp"
            )
        }
    }
}
