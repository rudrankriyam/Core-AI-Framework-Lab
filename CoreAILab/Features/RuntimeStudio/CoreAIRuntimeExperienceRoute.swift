import Foundation

struct CoreAIRuntimeExperienceRoute: Hashable {
    let experienceID: String

    var unavailableDescription: String {
        "The experience “\(experienceID)” is not available in the current runtime registry or on this platform."
    }
}
