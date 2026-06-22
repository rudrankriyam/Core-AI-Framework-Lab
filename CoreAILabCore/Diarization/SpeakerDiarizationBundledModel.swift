import CoreAI
import Foundation

enum SpeakerDiarizationBundledModel {
    static let directoryName = "Diarization"
    static let assetFilename = "CAMPPlus192_float16_600f.aimodel"

    static func url(in bundle: Bundle = .main) throws -> URL {
        guard let resourcesURL = bundle.url(
            forResource: directoryName,
            withExtension: nil
        ) else {
            throw SpeakerDiarizationError.bundledModelMissing
        }

        let assetURL = resourcesURL.appending(
            path: assetFilename,
            directoryHint: .isDirectory
        )
        guard AIModelAsset.isValid(at: assetURL) else {
            throw SpeakerDiarizationError.invalidBundledModel
        }
        return assetURL
    }
}
