import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class SpeakerDiarizationWatcherModel {
    var player: AVPlayer?
    var currentTime = Double.zero
    var isPlaying = false

    @ObservationIgnored
    private var clockTask: Task<Void, Never>?
    @ObservationIgnored
    private var isAccessingSecurityScopedResource = false
    @ObservationIgnored
    private var securityScopedURL: URL?
    @ObservationIgnored
    private var durationSeconds = Double.zero

    func load(url: URL?, summary: SpeakerDiarizationMediaSummary?) {
        reset()
        guard let url, let summary else {
            return
        }

        isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()
        securityScopedURL = url
        durationSeconds = summary.durationSeconds
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .pause
        self.player = player
        startClock(for: player)
    }

    func togglePlayback() {
        guard let player else {
            return
        }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= durationSeconds {
                seek(to: .zero)
            }
            player.play()
            isPlaying = true
        }
    }

    func restart() {
        guard let player else {
            return
        }

        seek(to: .zero)
        player.play()
        isPlaying = true
    }

    func reset() {
        clockTask?.cancel()
        clockTask = nil
        player?.pause()
        player = nil
        currentTime = .zero
        isPlaying = false
        durationSeconds = .zero
        if isAccessingSecurityScopedResource {
            securityScopedURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScopedResource = false
        }
        securityScopedURL = nil
    }

    private func startClock(for player: AVPlayer) {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                updateState(from: player)
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    private func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = seconds
    }

    private func updateState(from player: AVPlayer) {
        let seconds = player.currentTime().seconds
        currentTime = if seconds.isFinite {
            min(max(0, seconds), durationSeconds)
        } else {
            .zero
        }
        isPlaying = player.timeControlStatus == .playing
    }
}
