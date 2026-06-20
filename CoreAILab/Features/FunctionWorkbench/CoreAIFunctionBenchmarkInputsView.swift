import SwiftUI

struct CoreAIFunctionBenchmarkInputsView: View {
    let inputPlans: [CoreAIFunctionInputPlan]

    var body: some View {
        DisclosureGroup("Inputs") {
            ForEach(inputPlans) { plan in
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.name)
                        .font(.body.monospaced())
                    Text(description(for: plan))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func description(for plan: CoreAIFunctionInputPlan) -> String {
        let shape = plan.shape.isEmpty
            ? "scalar"
            : plan.shape.map(String.init).joined(separator: " × ")
        if plan.generator == .random {
            return "\(shape) · seeded random · seed \(plan.seed)"
        }
        return "\(shape) · zeros"
    }
}
