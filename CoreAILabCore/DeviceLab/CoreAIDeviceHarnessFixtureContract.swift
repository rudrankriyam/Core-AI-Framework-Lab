import Foundation

enum CoreAIDeviceHarnessFixtureContract {
    static let artifact = CoreAIDeviceArtifactIdentity(
        identifier: "CoreAILabTensorFixture.aimodel",
        sha256Digest: "c79fbfe17650c929af142bd353d60ab6aadd4a679ea86c37b9225667eeac7adc",
        byteCount: 1_694
    )

    static let configuration = CoreAIDeviceConfigurationIdentity(
        identifier: "physical-ios-fixture-v1",
        sha256Digest: "ba9e4ba3c35b3b91f05d6c18f594558d3f68e2ddc41efb28e6ff347bb2fef5b6",
        preferredComputeUnit: .automatic,
        expectsFrequentReshapes: false,
        contextTokens: nil,
        staticInputShapes: [
            "tokens": [1, 4],
            "values": [1, 4],
        ]
    )

    static let expectation = CoreAIDeviceEvidenceExpectation(
        artifact: artifact,
        configurationIdentifier: configuration.identifier,
        configurationSHA256Digest: configuration.sha256Digest
    )

    static let shapeRequest = CoreAIDeviceShapeAuthoringRequest(
        requestedContextTokens: nil,
        maximumContextTokens: nil,
        expectsFrequentReshapes: configuration.expectsFrequentReshapes,
        shapes: configuration.staticInputShapes.keys.sorted().map { name in
            CoreAIDeviceShapeDefinition(
                id: name,
                dimensions: configuration.staticInputShapes[name, default: []]
                    .map(Optional.some)
            )
        }
    )
}
