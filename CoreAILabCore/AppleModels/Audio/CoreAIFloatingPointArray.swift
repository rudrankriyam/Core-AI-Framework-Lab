import CoreAI
import Foundation

enum CoreAIFloatingPointArray {
    static func read(_ array: NDArray) throws -> [Float] {
        switch array.scalarType {
        case .float16:
            read(array, as: Float16.self)
        case .float32:
            read(array, as: Float.self)
        default:
            throw AppleAudioError.unsupportedScalarType(String(describing: array.scalarType))
        }
    }

    private static func read<Element>(
        _ array: NDArray,
        as type: Element.Type
    ) -> [Float] where Element: BinaryFloatingPoint & BitwiseCopyable {
        array.view(as: type).withUnsafePointer { pointer, shape, strides in
            let dimensions = (0..<shape.count).map { shape[$0] }
            let count = dimensions.reduce(1, *)
            return (0..<count).map { flatIndex in
                var remainder = flatIndex
                var offset = 0
                for dimension in dimensions.indices.reversed() {
                    let coordinate = remainder % dimensions[dimension]
                    remainder /= dimensions[dimension]
                    offset += coordinate * strides[dimension]
                }
                return Float(pointer[offset])
            }
        }
    }
}
