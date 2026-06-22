import SwiftUI

struct SpeakerDiarizationWaveformView: View {
    let waveform: SpeakerDiarizationWaveform
    let turns: [SpeakerDiarizationTurn]
    let playheadTime: Double

    var body: some View {
        Canvas { context, size in
            drawTurnBands(in: context, size: size)
            drawCenterLine(in: context, size: size)
            drawWaveform(in: context, size: size)
            drawPlayhead(in: context, size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Waveform timeline")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        if turns.isEmpty {
            "Media duration \(SpeakerDiarizationTimeFormatter.format(waveform.durationSeconds)); playhead at \(SpeakerDiarizationTimeFormatter.format(playheadTime)); no speaker turns generated yet."
        } else {
            "Media duration \(SpeakerDiarizationTimeFormatter.format(waveform.durationSeconds)); playhead at \(SpeakerDiarizationTimeFormatter.format(playheadTime)); \(turns.count.formatted()) speaker turns."
        }
    }

    private func drawTurnBands(
        in context: GraphicsContext,
        size: CGSize
    ) {
        for turn in turns {
            let startX = xPosition(for: turn.startTime, width: size.width)
            let endX = xPosition(for: turn.endTime, width: size.width)
            let rect = CGRect(
                x: startX,
                y: 0,
                width: max(1, endX - startX),
                height: size.height
            )
            context.fill(
                Path(rect),
                with: .color(color(for: turn.speakerName).opacity(0.16))
            )
        }
    }

    private func drawCenterLine(
        in context: GraphicsContext,
        size: CGSize
    ) {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height / 2))
        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
    }

    private func drawWaveform(
        in context: GraphicsContext,
        size: CGSize
    ) {
        guard !waveform.magnitudes.isEmpty else {
            return
        }
        let step = size.width / Double(waveform.magnitudes.count)
        let barWidth = max(1, step * 0.52)
        for (index, magnitude) in waveform.magnitudes.enumerated() {
            let x = (Double(index) * step) + ((step - barWidth) / 2)
            let height = max(2, Double(size.height) * 0.42 * magnitude)
            let rect = CGRect(
                x: x,
                y: (Double(size.height) - height) / 2,
                width: barWidth,
                height: height
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: barWidth / 2),
                with: .color(.primary.opacity(0.72))
            )
        }
    }

    private func drawPlayhead(
        in context: GraphicsContext,
        size: CGSize
    ) {
        let x = xPosition(for: playheadTime, width: size.width)
        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(path, with: .color(.orange), lineWidth: 2)

        let marker = CGRect(
            x: x - 4,
            y: 0,
            width: 8,
            height: 8
        )
        context.fill(
            Path(ellipseIn: marker),
            with: .color(.orange)
        )
    }

    private func xPosition(for time: Double, width: Double) -> Double {
        guard waveform.durationSeconds > 0 else {
            return 0
        }
        let progress = min(1, max(0, time / waveform.durationSeconds))
        return progress * width
    }

    private func color(for speakerName: String) -> Color {
        switch speakerName {
        case "Speaker 1":
            .blue
        case "Speaker 2":
            .teal
        default:
            .purple
        }
    }
}
