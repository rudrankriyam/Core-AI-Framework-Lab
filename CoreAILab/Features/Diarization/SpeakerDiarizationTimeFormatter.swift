import Foundation

enum SpeakerDiarizationTimeFormatter {
    static func format(_ seconds: Double) -> String {
        let boundedSeconds = seconds.isFinite ? max(seconds, 0) : 0
        if boundedSeconds > 0, boundedSeconds < 1 {
            let hundredths = min(
                99,
                max(1, Int((boundedSeconds * 100).rounded(.down)))
            )
            return "0:00.\(padded(hundredths))"
        }

        let totalSeconds = Int(boundedSeconds.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours):\(padded(minutes)):\(padded(seconds))"
        }
        return "\(minutes):\(padded(seconds))"
    }

    private static func padded(_ value: Int) -> String {
        value < 10 ? "0\(value)" : value.formatted()
    }
}
