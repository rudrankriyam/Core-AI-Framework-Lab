import CoreAI
import Foundation

enum CoreAITensorFactory {
    static func makeArray(
        descriptor: NDArrayDescriptor,
        plan: CoreAIFunctionInputPlan
    ) throws -> NDArray {
        guard CoreAITensorScalarSupport.isGeneratable(descriptor.scalarType) else {
            throw CoreAIFunctionWorkbenchError.unsupportedScalarType(
                String(describing: descriptor.scalarType)
            )
        }
        let resolved = try CoreAITensorShapeValidator.resolve(
            descriptor: descriptor,
            requestedShape: plan.shape,
            inputName: plan.name
        )
        var array = NDArray(descriptor: resolved)
        var random = CoreAISeededRandomNumberGenerator(seed: plan.seed)

        switch descriptor.scalarType {
        case .bool:
            fill(&array, as: Bool.self) {
                plan.generator == .zeros ? false : random.next() & 1 == 1
            }
        case .int8:
            fill(&array, as: Int8.self) {
                plan.generator == .zeros ? 0 : Int8(truncatingIfNeeded: random.next())
            }
        case .int16:
            fill(&array, as: Int16.self) {
                plan.generator == .zeros ? 0 : Int16(truncatingIfNeeded: random.next())
            }
        case .int32:
            fill(&array, as: Int32.self) {
                plan.generator == .zeros ? 0 : Int32(truncatingIfNeeded: random.next())
            }
        case .int64:
            fill(&array, as: Int64.self) {
                plan.generator == .zeros ? 0 : Int64(bitPattern: random.next())
            }
        case .uint8:
            fill(&array, as: UInt8.self) {
                plan.generator == .zeros ? 0 : UInt8(truncatingIfNeeded: random.next())
            }
        case .uint16:
            fill(&array, as: UInt16.self) {
                plan.generator == .zeros ? 0 : UInt16(truncatingIfNeeded: random.next())
            }
        case .uint32:
            fill(&array, as: UInt32.self) {
                plan.generator == .zeros ? 0 : UInt32(truncatingIfNeeded: random.next())
            }
        case .uint64:
            fill(&array, as: UInt64.self) {
                plan.generator == .zeros ? 0 : random.next()
            }
        case .float16:
            fill(&array, as: Float16.self) {
                plan.generator == .zeros ? 0 : Float16(random.nextUnitDouble() * 2 - 1)
            }
        case .float32:
            fill(&array, as: Float.self) {
                plan.generator == .zeros ? 0 : Float(random.nextUnitDouble() * 2 - 1)
            }
        case .float64:
            fill(&array, as: Double.self) {
                plan.generator == .zeros ? 0 : random.nextUnitDouble() * 2 - 1
            }
        default:
            throw CoreAIFunctionWorkbenchError.unsupportedScalarType(
                String(describing: descriptor.scalarType)
            )
        }
        return array
    }

    private static func fill<Element: BitwiseCopyable>(
        _ array: inout NDArray,
        as type: Element.Type,
        nextValue: () -> Element
    ) {
        var view = array.mutableView(as: type)
        view.withUnsafeMutablePointer { pointer, shape, strides in
            let dimensions = (0..<shape.count).map { shape[$0] }
            let elementCount = dimensions.reduce(1, *)
            for flatIndex in 0..<elementCount {
                pointer[offset(for: flatIndex, shape: dimensions, strides: strides)] = nextValue()
            }
        }
    }

    private static func offset(
        for flatIndex: Int,
        shape: [Int],
        strides: Span<Int>
    ) -> Int {
        var remaining = flatIndex
        var offset = 0
        for dimension in shape.indices.reversed() {
            let coordinate = remaining % shape[dimension]
            remaining /= shape[dimension]
            offset += coordinate * strides[dimension]
        }
        return offset
    }
}
