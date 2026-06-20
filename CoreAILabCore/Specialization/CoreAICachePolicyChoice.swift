import CoreAI
import Foundation

enum CoreAICachePolicyChoice: Sendable {
    case standard

    var policy: AIModelCache.Policy {
        .default
    }
}
