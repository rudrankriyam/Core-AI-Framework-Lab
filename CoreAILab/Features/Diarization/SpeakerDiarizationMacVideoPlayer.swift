#if os(macOS)
import AVFoundation
import AVKit
import SwiftUI

struct SpeakerDiarizationMacVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        Self.makePlayerView(player: player)
    }

    func updateNSView(_ playerView: AVPlayerView, context: Context) {
        if playerView.player !== player {
            playerView.player = player
        }
    }

    static func dismantleNSView(_ playerView: AVPlayerView, coordinator: Void) {
        playerView.player = nil
    }

    static func makePlayerView(player: AVPlayer) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.videoGravity = .resizeAspect
        playerView.updatesNowPlayingInfoCenter = false
        playerView.allowsVideoFrameAnalysis = false
        return playerView
    }
}
#endif
