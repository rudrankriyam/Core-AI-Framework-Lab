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

    var summary: String {
        switch self {
        case .source:
            "Define the recipe identity, source revision, and Python module."
        case .exampleInputs:
            "Describe deterministic inputs for conversion and validation."
        case .dynamicDimensions:
            "Name the dimensions that may vary at runtime."
        case .state:
            "Describe mutable tensors carried between function calls."
        case .externalization:
            "Choose resources that live outside the compiled model asset."
        case .functions:
            "Define callable entry points and their typed inputs and outputs."
        case .diagnostics:
            "Review source operators the Core AI converter cannot lower."
        case .rewrites:
            "Inspect the built-in catalog of supported graph rewrites."
        case .generatedArtifacts:
            "Review generated stubs without executing authored code."
        case .pipeline:
            "Connect typed assets into a validated pipeline contract."
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
