#if os(macOS)
import SwiftUI

struct CoreAIConversionSetupView: View {
    @Bindable var workspace: CoreAIConversionWorkspaceModel
    let chooseRepository: () -> Void
    let chooseOutputDirectory: () -> Void
    let chooseUVExecutable: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Model", selection: $workspace.selectedModelID) {
                    ForEach(workspace.groups) { group in
                        Section(group.category.rawValue) {
                            ForEach(group.models) { model in
                                Text(recipeTitle(model))
                                    .tag(model.id as String?)
                            }
                        }
                    }
                }

                LabeledContent("Source", value: workspace.selectedModelSubtitle)

                if workspace.supportsPrecisionSelection {
                    Picker("Compute precision", selection: $workspace.selectedPrecision) {
                        Text("Recipe default")
                            .tag(nil as CoreAIConversionPrecision?)
                        ForEach(workspace.supportedPrecisions) { precision in
                            Text(precision.title)
                                .tag(precision as CoreAIConversionPrecision?)
                        }
                    }
                }
            } header: {
                Label("Recipe", systemImage: "shippingbox")
            }
            .disabled(configurationIsLocked)

            Section {
                CoreAIConversionPathRow(
                    title: "Apple repository",
                    url: workspace.repositoryURL,
                    fallback: "Choose apple/coreai-models",
                    actionTitle: "Choose Repository",
                    action: chooseRepository
                )

                CoreAIConversionPathRow(
                    title: "Output folder",
                    url: workspace.outputDirectoryURL,
                    fallback: "Choose an output folder",
                    actionTitle: "Choose Output Folder",
                    action: chooseOutputDirectory
                )

                CoreAIConversionPathRow(
                    title: "uv executable",
                    url: workspace.uvExecutableURL,
                    fallback: "uv was not found",
                    actionTitle: "Choose uv Executable",
                    action: chooseUVExecutable
                )
            } header: {
                Label("Workspace", systemImage: "folder")
            }
            .disabled(configurationIsLocked)

            Section {
                Toggle(
                    "Overwrite matching artifacts",
                    isOn: $workspace.overwriteExistingArtifacts
                )
                Text("Source weights remain in the upstream cache. Core AI Lab does not redistribute or relicense them.")
                    .foregroundStyle(.secondary)
            } header: {
                Label("Options", systemImage: "switch.2")
            }
            .disabled(configurationIsLocked)

            Section {
                if let report = workspace.environmentReport {
                    ForEach(report.checks) { check in
                        CoreAIConversionEnvironmentCheckView(check: check)
                    }
                } else {
                    Text("Run the environment check before converting.")
                        .foregroundStyle(.secondary)
                }

                Button(
                    "Check Environment",
                    systemImage: "checkmark.circle",
                    action: checkEnvironment
                )
                .disabled(workspace.phase.isBusy)
            } header: {
                Label("Environment", systemImage: "checkmark.shield")
            }

            Section {
                if workspace.canCancelConversion {
                    Button(
                        "Cancel Conversion",
                        systemImage: "stop.fill",
                        role: .destructive,
                        action: workspace.cancelConversion
                    )
                    .keyboardShortcut(.cancelAction)
                } else {
                    Button(
                        "Start Conversion",
                        systemImage: "play.fill",
                        action: workspace.startConversion
                    )
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!workspace.canStartConversion)
                }
            } footer: {
                Text("The first run can create a Python environment and download many gigabytes. The evidence pane keeps the original converter output visible.")
            }
        }
        .formStyle(.grouped)
    }

    private func recipeTitle(_ model: AppleCoreAIModel) -> String {
        if let variant = model.variant {
            "\(model.shortName) · \(variant)"
        } else {
            model.shortName
        }
    }

    private func checkEnvironment() {
        Task {
            await workspace.refreshEnvironment()
        }
    }

    private var configurationIsLocked: Bool {
        workspace.phase.isBusy
    }
}
#endif
