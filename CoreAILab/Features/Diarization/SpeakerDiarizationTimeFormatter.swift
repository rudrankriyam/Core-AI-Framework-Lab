import Foundation

enum SpeakerDiarizationTimeFormatter {
    static func format(_ seconds: Double) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
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
