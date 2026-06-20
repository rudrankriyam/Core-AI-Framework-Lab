import CoreAI
import Foundation

struct CoreAITensorContract: Sendable, Equatable {
    let scalarType: NDArray.ScalarType
    let shape: [Int]
    let hasDynamicShape: Bool
    let minimumByteCount: Int

    var scalarTypeName: String {
        String(describing: scalarType)
    }

    var defaultRunShape: [Int] {
        shape.map { $0 > 0 ? $0 : 1 }
    }
}
