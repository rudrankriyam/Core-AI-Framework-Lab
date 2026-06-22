import SwiftUI

struct SpeakerDiarizationImportSection: View {
    let canRunStub: Bool
    let isRunningStub: Bool
    let importAction: () -> Void
    let runAction: () -> Void

    var body: some View {
        Section("Inputs") {
            HStack {
                Button("Choose Audio or Video", systemImage: "waveform", action: importAction)
                Button("Run Stub Diarization", systemImage: "person.2.wave.2", action: runAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRunStub || isRunningStub)
            }

            Text("Imported media is decoded locally into waveform buckets. A future Core AI diarizer can replace the stub engine without changing the timeline surface.")
                .foregroundStyle(.secondary)
        }
    }
}
