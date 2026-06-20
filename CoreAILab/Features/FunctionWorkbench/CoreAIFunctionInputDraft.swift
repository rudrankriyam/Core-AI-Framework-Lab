import Foundation
import Observation

@MainActor
@Observable
final class CoreAIFunctionInputDraft {
    let name: String
    let tensor: CoreAITensorContract
    var shapeText: String
    var generator: CoreAIFunctionInputGenerator = .zeros
    var seed: UInt64 = 42

    init?(contract: CoreAIFunctionValueContract) {
        guard case .tensor(let tensor) = contract.kind else {
            return nil
        }
        name = contract.name
        self.tensor = tensor
        shapeText = tensor.defaultRunShape.map(String.init).joined(separator: ", ")
    }

    func plan() throws -> CoreAIFunctionInputPlan {
        if tensor.shape.isEmpty,
           shapeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CoreAIFunctionInputPlan(
                name: name,
                shape: [],
                generator: generator,
                seed: seed
            )
        }
        let components = shapeText
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let shape = components.compactMap(Int.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty }),
              shape.count == components.count else {
            throw CoreAIFunctionWorkbenchError.invalidShape(
                name: name,
                reason: "enter comma-separated integer dimensions."
            )
        }
        return CoreAIFunctionInputPlan(
            name: name,
            shape: shape,
            generator: generator,
            seed: seed
        )
    }
}
