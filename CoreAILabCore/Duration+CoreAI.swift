extension Duration {
    var coreAISeconds: Double {
        let components = components
        return Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
    }

    var coreAIMilliseconds: Double {
        coreAISeconds * 1_000
    }
}
