import SwiftUI

struct CoreAIFunctionWorkbenchErrorPresenter: View {
    @Bindable var assetWorkspace: CoreAIAssetWorkspaceModel

    var body: some View {
        Color.clear
            .alert(
                "Function Workbench Error",
                isPresented: $assetWorkspace.isShowingError
            ) {
            } message: {
                Text(assetWorkspace.errorMessage ?? "The Core AI operation failed.")
            }
    }
}
