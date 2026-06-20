import Foundation

enum Wav2Vec2CTCDecoder {
    static let labels = [
        "-", "|", "E", "T", "A", "O", "N", "I", "H", "S", "R", "D", "L", "U", "M",
        "W", "C", "F", "G", "Y", "P", "B", "V", "K", "'", "X", "J", "Q", "Z",
    ]

    static func decode(emissions: [Float], shape: [Int]) throws -> String {
        guard shape.count == 3, shape[0] == 1, shape[2] == labels.count else {
            throw AppleAudioError.invalidOutputContract(
                "expected emissions shaped [1, time, \(labels.count)], got \(shape)"
            )
        }
        guard emissions.count == shape.reduce(1, *) else {
            throw AppleAudioError.invalidOutputContract(
                "the emission buffer does not match shape \(shape)"
            )
        }

        let timeSteps = shape[1]
        let labelCount = shape[2]
        var previousToken: Int?
        var decoded = ""

        for time in 0..<timeSteps {
            let offset = time * labelCount
            var bestToken = 0
            var bestValue = emissions[offset]
            for token in 1..<labelCount where emissions[offset + token] > bestValue {
                bestToken = token
                bestValue = emissions[offset + token]
            }

            defer { previousToken = bestToken }
            guard bestToken != previousToken, bestToken != 0 else { continue }
            decoded += labels[bestToken] == "|" ? " " : labels[bestToken]
        }

        return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
