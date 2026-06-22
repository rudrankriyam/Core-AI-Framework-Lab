import Foundation
import Observation

@MainActor
@Observable
final class CoreAIRecipeCatalogWorkspaceModel {
    typealias ImportOperation = @Sendable (URL) async throws -> CoreAIRecipeBundleSession

    enum Phase: Equatable {
        case idle
        case importing
        case imported
    }

    private(set) var catalog: CoreAIRecipeCatalogIndex?
    private(set) var catalogError: String?
    private(set) var importedSummary: CoreAIImportedRecipeBundleSummary?
    private(set) var codeApprovalState: CoreAIRecipeCodeApprovalState = .notRequired
    private(set) var phase: Phase = .idle
    private(set) var statusMessage = "Choose a recipe bundle directory to inspect and import."
    private(set) var errorMessage: String?
    var isShowingError = false

    @ObservationIgnored
    private let importOperation: ImportOperation
    @ObservationIgnored
    private var importedSession: CoreAIRecipeBundleSession?
    @ObservationIgnored
    private var activeImportID = UUID()

    init(
        bundle: Bundle = .main,
        importer: CoreAIRecipeBundleImporter = CoreAIRecipeBundleImporter(
            managedRootURL: CoreAIStorageLocation.recipeBundleRootURL
        )
    ) {
        importOperation = { url in
            try await importer.importBundle(at: url)
        }
        do {
            catalog = try CoreAIRecipeCatalog.loadCurated(bundle: bundle)
        } catch {
            catalogError = error.localizedDescription
        }
    }

    init(bundle: Bundle = .main, importOperation: @escaping ImportOperation) {
        self.importOperation = importOperation
        do {
            catalog = try CoreAIRecipeCatalog.loadCurated(bundle: bundle)
        } catch {
            catalogError = error.localizedDescription
        }
    }

    var entries: [CoreAIRecipeCatalogEntry] {
        catalog?.entries.sorted { $0.displayName < $1.displayName } ?? []
    }

    func importBundle(at url: URL) async {
        let importID = UUID()
        activeImportID = importID
        importedSession = nil
        importedSummary = nil
        codeApprovalState = .notRequired
        phase = .importing
        statusMessage = "Validating schema, inventory, paths, links, and hashes…"
        errorMessage = nil

        do {
            let session = try await importOperation(url)
            guard activeImportID == importID else { return }
            importedSession = session
            importedSummary = session.summary
            codeApprovalState = await session.codeApprovalState
            phase = .imported
            statusMessage = codeApprovalState == .approvalRequired
                ? "Imported as untrusted. Referenced code remains locked."
                : "Imported as untrusted. This bundle has no executable references."
        } catch is CancellationError {
            guard activeImportID == importID else { return }
            phase = .idle
            statusMessage = "Import cancelled."
        } catch {
            guard activeImportID == importID else { return }
            phase = .idle
            errorMessage = error.localizedDescription
            isShowingError = true
            statusMessage = "The bundle was not imported."
        }
    }

    func presentImportError(_ error: any Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    func approveReferencedCodeExecution() async {
        guard let importedSession else { return }
        await importedSession.approveReferencedCodeExecution()
        codeApprovalState = await importedSession.codeApprovalState
        statusMessage = "Referenced code is approved for this session, but has not been executed."
    }

    func revokeReferencedCodeExecutionApproval() async {
        guard let importedSession else { return }
        await importedSession.revokeReferencedCodeExecutionApproval()
        codeApprovalState = await importedSession.codeApprovalState
        statusMessage = "Referenced code is locked again."
    }
}
