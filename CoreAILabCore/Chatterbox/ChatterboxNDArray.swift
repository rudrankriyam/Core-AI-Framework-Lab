import CoreAI
import Foundation

enum ChatterboxNDArray {
    static func zerosFloat16(shape: [Int]) -> NDArray {
        var array = NDArray(shape: shape, scalarType: .float16)
        var view = array.mutableView(as: Float16.self)
        view.withUnsafeMutablePointer { pointer, shape, _ in
            let count = product(shape)
            for index in 0..<count {
                pointer[index] = 0
            }
        }
        return array
    }

    static func floats(from array: NDArray) throws -> [Float] {
        switch array.scalarType {
        case .float16:
            return readFloatingPoint(array, as: Float16.self)
        case .float32:
            return readFloatingPoint(array, as: Float.self)
        default:
            throw ChatterboxCoreAIError.unsupportedScalarType(
                String(describing: array.scalarType)
            )
        }
    }

    static func lastLogits(from array: NDArray) throws -> [Float] {
        guard array.shape.count == 3, let sequenceLength = array.shape.dropFirst().first,
              let vocabularySize = array.shape.last, sequenceLength > 0
        else {
            throw ChatterboxCoreAIError.invalidOutputShape(
                "Expected logits shaped [1, sequence, vocabulary], got \(array.shape)."
            )
        }

        switch array.scalarType {
        case .float16:
            return readLastLogits(
                array,
                as: Float16.self,
                sequenceLength: sequenceLength,
                vocabularySize: vocabularySize
            )
        case .float32:
            return readLastLogits(
                array,
                as: Float.self,
                sequenceLength: sequenceLength,
                vocabularySize: vocabularySize
            )
        default:
            throw ChatterboxCoreAIError.unsupportedScalarType(
                String(describing: array.scalarType)
            )
        }
    }

    static func patchCache(
        _ cache: inout NDArray,
        with updates: NDArray,
        at sequenceOffset: Int
    ) throws {
        guard cache.scalarType == .float16, updates.scalarType == .float16,
              cache.shape.count == 5, updates.shape.count == 5,
              cache.shape[0] == updates.shape[0],
              cache.shape[1] == updates.shape[1],
              cache.shape[2] == updates.shape[2],
              cache.shape[4] == updates.shape[4],
              sequenceOffset >= 0,
              sequenceOffset + updates.shape[3] <= cache.shape[3]
        else {
            throw ChatterboxCoreAIError.invalidOutputShape(
                "The T3 key/value cache update did not match the persistent cache."
            )
        }

        var destinationView = cache.mutableView(as: Float16.self)
        updates.view(as: Float16.self).withUnsafePointer {
            source, sourceShape, sourceStrides in
            destinationView.withUnsafeMutablePointer {
                destination, _, destinationStrides in
                for layer in 0..<sourceShape[0] {
                    for batch in 0..<sourceShape[1] {
                        for head in 0..<sourceShape[2] {
                            for position in 0..<sourceShape[3] {
                                for channel in 0..<sourceShape[4] {
                                    let sourceIndex =
                                        layer * sourceStrides[0]
                                        + batch * sourceStrides[1]
                                        + head * sourceStrides[2]
                                        + position * sourceStrides[3]
                                        + channel * sourceStrides[4]
                                    let destinationIndex =
                                        layer * destinationStrides[0]
                                        + batch * destinationStrides[1]
                                        + head * destinationStrides[2]
                                        + (sequenceOffset + position) * destinationStrides[3]
                                        + channel * destinationStrides[4]
                                    destination[destinationIndex] = source[sourceIndex]
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private static func readFloatingPoint<T>(
        _ array: NDArray,
        as type: T.Type
    ) -> [Float] where T: BinaryFloatingPoint & BitwiseCopyable {
        array.view(as: type).withUnsafePointer { pointer, shape, strides in
            let dimensions = (0..<shape.count).map { shape[$0] }
            let totalCount = dimensions.reduce(1, *)
            var values = [Float](repeating: 0, count: totalCount)
            for flatIndex in 0..<totalCount {
                var remaining = flatIndex
                var sourceIndex = 0
                for dimension in dimensions.indices.reversed() {
                    let coordinate = remaining % dimensions[dimension]
                    remaining /= dimensions[dimension]
                    sourceIndex += coordinate * strides[dimension]
                }
                values[flatIndex] = Float(pointer[sourceIndex])
            }
            return values
        }
    }

    private static func readLastLogits<T>(
        _ array: NDArray,
        as type: T.Type,
        sequenceLength: Int,
        vocabularySize: Int
    ) -> [Float] where T: BinaryFloatingPoint & BitwiseCopyable {
        array.view(as: type).withUnsafePointer { pointer, _, strides in
            let sequenceOffset = (sequenceLength - 1) * strides[1]
            return (0..<vocabularySize).map {
                Float(pointer[sequenceOffset + $0 * strides[2]])
            }
        }
    }

    private static func product(_ shape: Span<Int>) -> Int {
        var result = 1
        for index in 0..<shape.count {
            result *= shape[index]
        }
        return result
    }
}
