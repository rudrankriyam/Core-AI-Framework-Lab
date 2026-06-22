struct CoreAIPipelineDimension: Codable, Hashable, Sendable {
    let name: String?
    let fixedSize: Int?
    let minimum: Int?
    let maximum: Int?

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
