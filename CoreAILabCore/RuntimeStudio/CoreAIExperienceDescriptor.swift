import Foundation

struct CoreAIExperienceDescriptor: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let summary: String
    let workload: CoreAIExperienceWorkload
    let adapter: CoreAIExperienceAdapter
    let modelIdentifier: String
    let systemImage: String
    let capabilities: [CoreAIExperienceCapability]
    let platforms: [AppleCoreAIPlatform]
}
