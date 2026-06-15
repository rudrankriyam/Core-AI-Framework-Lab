import Foundation

enum ChatterboxWaveFile {
    static let sampleRate = 24_000

    static func write(samples: [Float], to url: URL) throws {
        try data(samples: samples).write(to: url, options: .atomic)
    }

    static func data(samples: [Float]) -> Data {
        let bytesPerSample = 2
        let dataByteCount = samples.count * bytesPerSample
        var data = Data()
        data.reserveCapacity(44 + dataByteCount)

        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndian(UInt32(36 + dataByteCount))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(UInt32(sampleRate * bytesPerSample))
        data.appendLittleEndian(UInt16(bytesPerSample))
        data.appendLittleEndian(UInt16(16))
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndian(UInt32(dataByteCount))

        for sample in samples {
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
