import SwiftUI

enum CoreAIRecipeStudioPanel: String, CaseIterable, Hashable, Identifiable {
    case source
    case exampleInputs
    case dynamicDimensions
    case state
    case externalization
    case functions
    case diagnostics
    case rewrites
    case generatedArtifacts
    case pipeline

    var id: Self { self }

    var title: String {
        switch self {
        case .source:
            "Source & Module"
        case .exampleInputs:
            "Example Inputs"
        case .dynamicDimensions:
            "Dynamic Dimensions"
        case .state:
            "State"
        case .externalization:
            "Externalization"
        case .functions:
            "Functions"
        case .diagnostics:
            "Unsupported Ops"
        case .rewrites:
            "Rewrite Catalog"
        case .generatedArtifacts:
            "Generated Stubs"
        case .pipeline:
            "Pipeline Studio"
        }
    }

    var systemImage: String {
        switch self {
        case .source:
            "shippingbox"
        case .exampleInputs:
            "square.and.pencil"
        case .dynamicDimensions:
            "arrow.left.and.right"
        case .state:
            "memorychip"
        case .externalization:
            "externaldrive"
        case .functions:
            "function"
        case .diagnostics:
            "exclamationmark.triangle"
        case .rewrites:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .generatedArtifacts:
            "doc.badge.gearshape"
        case .pipeline:
            "point.3.connected.trianglepath.dotted"
        }
    }
}

extension View {
    @ViewBuilder
    func coreAIRecipeIdentifierInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
        #endif
    }

    @ViewBuilder
    func coreAIRecipeIntegerInput() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }
}
