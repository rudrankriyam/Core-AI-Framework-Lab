import CoreAI
import Foundation

enum CoreAIOutputInspector {
    private static let sampleLimit = 65_536
    private static let previewLimit = 8

    static func summarize(
        name: String,
        array: NDArray
    ) -> CoreAIFunctionOutputSummary {
        switch array.scalarType {
        case .bool:
            numericSummary(name: name, array: array, as: Bool.self) {
                ($0 ? 1 : 0, $0 ? "true" : "false")
            }
        case .int8:
            numericSummary(name: name, array: array, as: Int8.self) {
                (Double($0), String($0))
            }
        case .int16:
            numericSummary(name: name, array: array, as: Int16.self) {
                (Double($0), String($0))
            }
        case .int32:
            numericSummary(name: name, array: array, as: Int32.self) {
                (Double($0), String($0))
            }
        case .int64:
            numericSummary(name: name, array: array, as: Int64.self) {
                (Double($0), String($0))
            }
        case .uint8:
            numericSummary(name: name, array: array, as: UInt8.self) {
                (Double($0), String($0))
            }
        case .uint16:
            numericSummary(name: name, array: array, as: UInt16.self) {
                (Double($0), String($0))
            }
        case .uint32:
            numericSummary(name: name, array: array, as: UInt32.self) {
                (Double($0), String($0))
            }
        case .uint64:
            numericSummary(name: name, array: array, as: UInt64.self) {
                (Double($0), String($0))
            }
        case .float16:
            numericSummary(name: name, array: array, as: Float16.self) {
                let value = Double($0)
                return (value, formatted(value))
            }
        case .float32:
            numericSummary(name: name, array: array, as: Float.self) {
                let value = Double($0)
                return (value, formatted(value))
            }
        case .float64:
            numericSummary(name: name, array: array, as: Double.self) {
                ($0, formatted($0))
            }
        default:
            CoreAIFunctionOutputSummary(
                name: name,
                typeDescription: String(describing: array.scalarType),
                shape: array.shape,
                strides: array.strides,
                elementCount: safeProduct(array.shape),
                sampledElementCount: 0,
                minimum: nil,
                maximum: nil,
                mean: nil,
                nonFiniteCount: 0,
                preview: []
            )
        }
    }

    static func imageSummary(
        name: String,
        width: Int,
        height: Int,
        pixelFormatType: UInt32
    ) -> CoreAIFunctionOutputSummary {
        CoreAIFunctionOutputSummary(
            name: name,
            typeDescription: "image, pixel format \(pixelFormatType)",
            shape: [height, width],
            strides: [],
            elementCount: safeProduct([height, width]),
            sampledElementCount: 0,
            minimum: nil,
            maximum: nil,
            mean: nil,
            nonFiniteCount: 0,
            preview: []
        )
    }

    private static func numericSummary<Element: BitwiseCopyable>(
        name: String,
        array: NDArray,
        as type: Element.Type,
        transform: (Element) -> (number: Double, text: String)
    ) -> CoreAIFunctionOutputSummary {
        let shape = array.shape
        let strides = array.strides
        let elementCount = safeProduct(shape)
        let sampledElementCount = min(elementCount, sampleLimit)
        var minimum: Double?
        var maximum: Double?
        var sum = 0.0
        var finiteCount = 0
        var nonFiniteCount = 0
        var preview: [String] = []

        array.view(as: type).withUnsafePointer { pointer, _, viewStrides in
            for sampleIndex in 0..<sampledElementCount {
                let flatIndex = sampledElementCount == elementCount
                    ? sampleIndex
                    : distributedIndex(
                        sampleIndex,
                        count: elementCount,
                        sampleCount: sampledElementCount
                    )
                let value = transform(
                    pointer[offset(for: flatIndex, shape: shape, strides: viewStrides)]
                )
                if preview.count < previewLimit {
                    preview.append(value.text)
                }
                if value.number.isFinite {
                    minimum = min(minimum ?? value.number, value.number)
                    maximum = max(maximum ?? value.number, value.number)
                    sum += value.number
                    finiteCount += 1
                } else {
                    nonFiniteCount += 1
                }
            }
        }

        return CoreAIFunctionOutputSummary(
            name: name,
            typeDescription: String(describing: array.scalarType),
            shape: shape,
            strides: strides,
            elementCount: elementCount,
            sampledElementCount: sampledElementCount,
            minimum: minimum,
            maximum: maximum,
            mean: finiteCount > 0 ? sum / Double(finiteCount) : nil,
            nonFiniteCount: nonFiniteCount,
            preview: preview
        )
    }

    private static func safeProduct(_ values: [Int]) -> Int {
        values.reduce(1) { result, value in
            let (product, overflow) = result.multipliedReportingOverflow(by: value)
            return overflow ? Int.max : product
        }
    }

    private static func distributedIndex(
        _ sampleIndex: Int,
        count: Int,
        sampleCount: Int
    ) -> Int {
        let quotient = count / sampleCount
        let remainder = count % sampleCount
        return sampleIndex * quotient + sampleIndex * remainder / sampleCount
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

    private static func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.significantDigits(1...6)))
    }
}
