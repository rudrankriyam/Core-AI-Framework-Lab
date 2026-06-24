import SwiftUI

struct AppleLanguageResponseView: View {
    let response: String

    var body: some View {
        Section {
            if response.isEmpty {
                ContentUnavailableView(
                    "No Response Yet",
                    systemImage: "text.bubble",
                    description: Text("Import Qwen, enter a prompt, and generate locally.")
                )
            } else {
                Text(response)
                    .textSelection(.enabled)
            }
        } header: {
            Label("Response", systemImage: "text.bubble")
        }
    }
}
