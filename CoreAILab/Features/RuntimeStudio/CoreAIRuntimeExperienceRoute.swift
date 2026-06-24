import Foundation

struct CoreAIRuntimeExperienceRoute: Hashable {
    let experienceID: String

    var unavailableDescription: String {
        "The experience “\(experienceID)” is no longer in the runtime registry or isn't available on this platform."
    }
}
