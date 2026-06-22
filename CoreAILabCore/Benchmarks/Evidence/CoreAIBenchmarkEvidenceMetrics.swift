import Foundation

struct CoreAIBenchmarkEvidenceMetrics: Codable, Sendable, Equatable {
    let peakResidentMemoryBytes: UInt64?
    let energyJoules: Double?
    let memoryMeasurementStatus: String
    let energyMeasurementStatus: String

    init(
        peakResidentMemoryBytes: UInt64? = nil,
        energyJoules: Double? = nil,
        memoryMeasurementStatus: String = "notMeasured",
        energyMeasurementStatus: String = "notMeasured"
    ) {
        self.peakResidentMemoryBytes = peakResidentMemoryBytes
        self.energyJoules = energyJoules
        self.memoryMeasurementStatus = memoryMeasurementStatus
        self.energyMeasurementStatus = energyMeasurementStatus
    }

    private enum CodingKeys: String, CodingKey {
        case peakResidentMemoryBytes
        case energyJoules
        case memoryMeasurementStatus
        case energyMeasurementStatus
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let peakResidentMemoryBytes {
            try container.encode(
                peakResidentMemoryBytes,
                forKey: .peakResidentMemoryBytes
            )
        } else {
            try container.encodeNil(forKey: .peakResidentMemoryBytes)
        }
        if let energyJoules {
            try container.encode(energyJoules, forKey: .energyJoules)
        } else {
            try container.encodeNil(forKey: .energyJoules)
        }
        try container.encode(
            memoryMeasurementStatus,
            forKey: .memoryMeasurementStatus
        )
        try container.encode(
            energyMeasurementStatus,
            forKey: .energyMeasurementStatus
        )
    }
}
