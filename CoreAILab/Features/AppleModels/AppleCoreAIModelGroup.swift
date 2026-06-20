import Foundation

struct AppleCoreAIModelGroup: Identifiable {
    let category: AppleCoreAIModelCategory
    let models: [AppleCoreAIModel]

    var id: AppleCoreAIModelCategory { category }
}
