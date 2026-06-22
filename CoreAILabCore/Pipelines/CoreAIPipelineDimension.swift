struct CoreAIPipelineDimension: Codable, Hashable, Sendable {
    var name: String?
    var fixedSize: Int?
    var minimum: Int?
    var maximum: Int?

    static func fixed(_ size: Int) -> Self {
        Self(name: nil, fixedSize: size, minimum: nil, maximum: nil)
    }

    static func dynamic(
        _ name: String,
        minimum: Int? = nil,
        maximum: Int? = nil
    ) -> Self {
        Self(
            name: name,
            fixedSize: nil,
            minimum: minimum,
            maximum: maximum
        )
    }
}
