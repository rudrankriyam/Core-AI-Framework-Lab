import CoreAI
import CoreVideo
import Foundation

struct CoreAITensorDescriptorReport: Sendable, Equatable {
    let scalarType: String
    let shape: [Int]
    let rank: Int
    let hasDynamicShape: Bool
    let preferredStrides: [Int]
    let minimumByteCount: Int
}

struct CoreAIImageDescriptorReport: Sendable, Equatable {
    let height: Int
    let width: Int
    let pixelFormatType: OSType
}

enum CoreAIValueDescriptorExamples {
    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func report(for descriptor: NDArrayDescriptor) -> CoreAITensorDescriptorReport {
        CoreAITensorDescriptorReport(
            scalarType: String(describing: descriptor.scalarType),
            shape: descriptor.shape,
            rank: descriptor.rank,
            hasDynamicShape: descriptor.hasDynamicShape,
            preferredStrides: descriptor.preferredStrides,
            minimumByteCount: descriptor.minimumByteCount
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func report(for descriptor: ImageDescriptor) -> CoreAIImageDescriptorReport {
        CoreAIImageDescriptorReport(
            height: descriptor.height,
            width: descriptor.width,
            pixelFormatType: descriptor.pixelFormatType
        )
    }

    @available(iOS 27.0, macOS 27.0, tvOS 27.0, watchOS 27.0, visionOS 27.0, *)
    static func describe(_ descriptor: InferenceValue.Descriptor) -> String {
        switch descriptor {
        case .ndArray(let arrayDescriptor):
            let report = report(for: arrayDescriptor)
            return "tensor \(report.scalarType), shape: \(report.shape), bytes: \(report.minimumByteCount)"
        case .image(let imageDescriptor):
            let report = report(for: imageDescriptor)
            return "image \(report.width)x\(report.height), pixel format: \(report.pixelFormatType)"
        @unknown default:
            return "unknown descriptor"
        }
    }
}
