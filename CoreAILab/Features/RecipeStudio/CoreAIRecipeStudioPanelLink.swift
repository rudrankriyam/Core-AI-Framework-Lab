import SwiftUI

struct CoreAIRecipeStudioPanelLink: View {
    let panel: CoreAIRecipeStudioPanel

    var body: some View {
        NavigationLink(value: panel) {
            Label(panel.title, systemImage: panel.systemImage)
        }
        .help(panel.summary)
        .accessibilityHint(panel.summary)
    }
}
