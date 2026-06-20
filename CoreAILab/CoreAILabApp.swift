import SwiftData
import SwiftUI

@main
@MainActor
struct CoreAILabApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try CoreAIProjectModelContainer.makePersistent()
        } catch {
            fatalError("Unable to open the Core AI Lab project library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
