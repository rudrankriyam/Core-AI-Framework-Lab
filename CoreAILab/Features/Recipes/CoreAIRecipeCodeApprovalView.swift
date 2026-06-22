import SwiftUI

struct CoreAIRecipeCodeApprovalView: View {
    let state: CoreAIRecipeCodeApprovalState
    let onApprove: () -> Void
    let onRevoke: () -> Void

    @State private var isConfirmingApproval = false

    var body: some View {
        switch state {
        case .approvalRequired:
            Label(
                "Python, Swift, or custom code is locked until you explicitly approve it.",
                systemImage: "lock.trianglebadge.exclamationmark"
            )
            .foregroundStyle(.orange)

            Button("Approve Referenced Code") {
                isConfirmingApproval = true
            }
            .confirmationDialog(
                "Approve Referenced Code?",
                isPresented: $isConfirmingApproval
            ) {
                Button("Approve for This Session", action: onApprove)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Approval unlocks the listed code references for this session. It does not execute them.")
            }
        case .approved:
            Label(
                "Code references are approved for this session. Nothing has been executed.",
                systemImage: "checkmark.shield"
            )
            .foregroundStyle(.green)
            Button("Revoke Code Approval", action: onRevoke)
        case .notRequired:
            Label(
                "No executable references are declared.",
                systemImage: "doc.badge.checkmark"
            )
        }
    }
}
