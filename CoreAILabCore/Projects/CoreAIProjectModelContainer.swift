import Foundation
import SwiftData

@MainActor
enum CoreAIProjectModelContainer {
    static func makePersistent(
        storeURL: URL = CoreAIStorageLocation.projectStoreURL,
        fileManager: FileManager = .default
    ) throws -> ModelContainer {
        try fileManager.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let schema = Schema([
            LabProject.self,
            ModelArtifactRecord.self,
            ProjectArtifactLink.self,
            CoreAISourceProvenanceRecord.self,
            CoreAISpecializationCacheRecord.self,
            CoreAIRecipeRevisionRecord.self,
            CoreAITargetProfileRecord.self,
            CoreAIRunRecord.self,
            CoreAIEvidenceRecord.self
        ])
        let configuration = ModelConfiguration(
            "CoreAIProjects",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            configurations: [configuration]
        )
    }
}
