import Foundation

enum CoreAIConversionPrecision: String, CaseIterable, Identifiable, Sendable {
    case float16
    case bfloat16
    case float32

    var id: Self { self }

    var title: String {
        switch self {
        case .float16:
            "Float16"
        case .bfloat16:
            "BFloat16"
        case .float32:
            "Float32"
        }
    }
}
