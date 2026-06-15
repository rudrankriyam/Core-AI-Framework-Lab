import SwiftUI

struct CoreAIRuntimeView: View {
    private let snapshot = CoreAIDiscoverySnapshot.current()
    private let catalog = CoreAIExampleCatalog.current

    var body: some View {
        NavigationStack {
            List {
                Section("Runtime") {
                    LabeledContent("Framework", value: snapshot.frameworkName)
                    LabeledContent("Device architecture", value: snapshot.deviceArchitectureName)
                }

                Section("Compute Units") {
                    ForEach(snapshot.availableComputeUnits, id: \.self) { unit in
                        Text(unit)
                    }
                }

                Section("Specialization") {
                    LabeledContent("Default", value: snapshot.defaultSpecializationDescription)
                    LabeledContent("CPU only", value: snapshot.cpuOnlySpecializationDescription)
                }

                Section("Examples") {
                    ForEach(catalog.examples) { example in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.title)
                                .font(.headline)
                            Text(example.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(example.sourceFile)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Core AI Runtime")
        }
    }
}
