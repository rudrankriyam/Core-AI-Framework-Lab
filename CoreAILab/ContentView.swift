import SwiftUI

struct ContentView: View {
    private let snapshot = CoreAIDiscoverySnapshot.current()

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
            }
            .navigationTitle("Core AI Lab")
        }
    }
}

