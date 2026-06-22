import Foundation

enum CoreAIRecipeStubGenerator {
    static func artifacts(
        for finding: CoreAIUnsupportedOperationFinding
    ) -> [CoreAIRecipeGeneratedArtifact] {
        let identifier = safeIdentifier(finding.operatorName)
        let operatorLiteral = pythonStringLiteral(finding.operatorName)
        let attribution = safeComment(
            "\(finding.modulePath) at \(finding.sourceFile):\(finding.sourceLine)"
        )

        let lowering = """
        from coreai._compiler.dialects import coreai

        # Generated for \(attribution)
        # This stub fails until the lowering returns a verified Core AI value.
        def lower_\(identifier)(values, node, location):
            raise NotImplementedError("Implement and parity-test \(operatorLiteral)")


        def register(converter):
            converter.register_torch_lowering("\(operatorLiteral)")(lower_\(identifier))
        """

        let metal = """
        #include <metal_stdlib>
        using namespace metal;

        // Generated for \(attribution)
        // Replace the signature and body only after confirming tensor layout.
        #error "Implement and parity-test \(identifier)_kernel before use"

        kernel void \(identifier)_kernel(
            device const float *input [[buffer(0)]],
            device float *output [[buffer(1)]],
            uint index [[thread_position_in_grid]]) {
            output[index] = input[index];
        }
        """

        return [
            CoreAIRecipeGeneratedArtifact(
                relativePath: "Generated/Lowerings/\(identifier)_lowering.py",
                kind: .customLowering,
                contents: lowering
            ),
            CoreAIRecipeGeneratedArtifact(
                relativePath: "Generated/Metal/\(identifier).metal",
                kind: .metalKernel,
                contents: metal
            )
        ]
    }

    private static func safeIdentifier(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            if (97...122).contains(scalar.value) || (48...57).contains(scalar.value) {
                Character(String(scalar))
            } else {
                "_"
            }
        }
        let collapsed = String(scalars).split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
        let candidate = String(
            (collapsed.isEmpty ? "unsupported_operation" : collapsed).prefix(80)
        )
        if candidate.first?.isNumber == true {
            return "op_\(candidate)"
        }
        return candidate
    }

    private static func pythonStringLiteral(_ value: String) -> String {
        value
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
            .replacing("\n", with: "\\n")
    }

    private static func safeComment(_ value: String) -> String {
        value
            .replacing("\r", with: " ")
            .replacing("\n", with: " ")
    }
}
