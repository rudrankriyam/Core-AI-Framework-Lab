import SwiftUI

struct CoreAIBenchmarkToolchainView: View {
    let toolchain: CoreAIBenchmarkToolchain

    var body: some View {
        DisclosureGroup("Toolchain") {
            if let xcodeVersionCode = toolchain.xcodeVersionCode {
                LabeledContent("Xcode version code", value: xcodeVersionCode)
            }
            if let xcodeBuild = toolchain.xcodeBuild {
                LabeledContent("Xcode build", value: xcodeBuild)
            }
            if let sdkName = toolchain.sdkName {
                LabeledContent("SDK", value: sdkName)
            }
            if let sdkBuild = toolchain.sdkBuild {
                LabeledContent("SDK build", value: sdkBuild)
            }
            if let compilerIdentifier = toolchain.compilerIdentifier {
                LabeledContent("Compiler", value: compilerIdentifier)
            }
            LabeledContent(
                "Swift compiler",
                value: toolchain.swiftCompilerVersionConstraint
            )
            LabeledContent(
                "Swift language mode",
                value: toolchain.swiftLanguageMode
            )
        }
    }
}
