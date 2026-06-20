import Foundation

enum CoreAIProjectRoute: Hashable {
    case project(UUID)
    case artifact(UUID)
    case inspect(UUID)
    case workbench(UUID)
}
