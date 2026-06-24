import SwiftUI

struct ChatterboxPromptSection: View {
    @Binding var prompt: String

    var body: some View {
        Section {
            TextField("What should Chatterbox say?", text: $prompt, axis: .vertical)
                .lineLimit(4...)

            Text("Expressive tags such as [laugh], [chuckle], [sigh], and [gasp] stay in the text. One generation supports about 10 seconds of speech.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Label("Speech", systemImage: "text.quote")
        }
    }
}
