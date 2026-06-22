import Foundation

enum ChatterboxWaveFile {
    static func write(
        samples: [Float],
        sampleRate: Int,
        to url: URL
    ) throws {
        try data(samples: samples, sampleRate: sampleRate)
            .write(to: url, options: .atomic)
    }

    static func data(samples: [Float], sampleRate: Int) throws -> Data {
        let bytesPerSample = 2
        guard (1...384_000).contains(sampleRate) else {
            throw ChatterboxCoreAIError.invalidWaveFile(
                "The WAV sample rate is outside the supported range."
            )
        }
        let (dataByteCount, dataSizeOverflow) = samples.count
            .multipliedReportingOverflow(by: bytesPerSample)
        let (riffByteCount, riffSizeOverflow) = 36.addingReportingOverflow(
            dataByteCount
        )
        let (byteRate, byteRateOverflow) = sampleRate.multipliedReportingOverflow(
            by: bytesPerSample
        )
        guard !dataSizeOverflow,
              !riffSizeOverflow,
              !byteRateOverflow,
              dataByteCount <= 200_000_000,
              riffByteCount <= Int(UInt32.max),
              dataByteCount <= Int(UInt32.max),
              byteRate <= Int(UInt32.max) else {
            throw ChatterboxCoreAIError.invalidWaveFile(
                "The generated waveform is too large for a PCM WAV file."
            )
        }
        let (reservedByteCount, reserveOverflow) = 44.addingReportingOverflow(
            dataByteCount
        )
        guard !reserveOverflow else {
            throw ChatterboxCoreAIError.invalidWaveFile(
                "The generated waveform exceeds the runtime integer range."
            )
        }
        var data = Data()
        data.reserveCapacity(reservedByteCount)

        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndian(UInt32(riffByteCount))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(byteRate))
        data.appendLittleEndian(UInt16(bytesPerSample))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(UInt32(dataByteCount))

        for sample in samples {
            guard sample.isFinite else {
                throw ChatterboxCoreAIError.invalidWaveFile(
                    "The generated waveform contains a non-finite sample."
                )
            }
            let clamped = min(max(sample, -1), 1)
            let pcm = Int16((clamped * Float(Int16.max)).rounded())
            data.appendLittleEndian(pcm)
        }
        return data
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) {
            append(contentsOf: $0)
        }
    }
}
