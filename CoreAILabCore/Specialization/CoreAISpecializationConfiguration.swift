import CoreAI
import Foundation

struct CoreAISpecializationConfiguration: Hashable, Sendable {
    let profile: CoreAISpecializationProfile
    let expectFrequentReshapes: Bool

    init(
        profile: CoreAISpecializationProfile,
        expectFrequentReshapes: Bool? = nil
    ) {
        self.profile = profile
        self.expectFrequentReshapes = expectFrequentReshapes
            ?? profile.options.expectFrequentReshapes
    }

    var options: SpecializationOptions {
        var options = profile.options
        options.expectFrequentReshapes = expectFrequentReshapes
        return options
    }
}
