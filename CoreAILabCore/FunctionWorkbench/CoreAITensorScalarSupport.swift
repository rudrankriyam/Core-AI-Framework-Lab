import CoreAI
import Foundation

enum CoreAITensorScalarSupport {
    static func isGeneratable(_ scalarType: NDArray.ScalarType) -> Bool {
        switch scalarType {
        case .bool,
             .int8, .int16, .int32, .int64,
             .uint8, .uint16, .uint32, .uint64,
             .float16, .float32, .float64:
            true
        default:
            false
        }
    }
}
