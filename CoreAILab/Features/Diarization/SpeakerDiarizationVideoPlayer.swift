import AVFoundation
import AVKit
import SwiftUI

struct SpeakerDiarizationVideoPlayer: View {
    let player: AVPlayer

    var body: some View {
#if os(macOS)
        SpeakerDiarizationMacVideoPlayer(player: player)
#else
        VideoPlayer(player: player)
#endif
    }
}
