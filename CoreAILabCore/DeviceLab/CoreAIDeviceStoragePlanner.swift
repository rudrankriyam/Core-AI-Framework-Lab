import Foundation

enum CoreAIDeviceStoragePlanner {
    static func plan(
        request: CoreAIDeviceStoragePlanRequest
    ) throws -> CoreAIDeviceStoragePlan {
        try request.validate()
        var appDownloadBytes: UInt64 = 0
        var onDemandDownloadBytes: UInt64 = 0

        for slice in request.slices {
            switch slice.deliveryMode {
            case .appDownload:
                appDownloadBytes = try adding(
                    appDownloadBytes,
                    slice.downloadByteCount,
                    path: "storagePlan.appDownloadBytes"
                )
            case .onDemand:
                onDemandDownloadBytes = try adding(
                    onDemandDownloadBytes,
                    slice.downloadByteCount,
                    path: "storagePlan.onDemandDownloadBytes"
                )
            }
        }

        var installedAssetBytes: UInt64 = 0
        for slice in request.slices {
            installedAssetBytes = try adding(
                installedAssetBytes,
                slice.installedByteCount,
                path: "storagePlan.installedAssetBytes"
            )
        }
        let peakRequiredDeviceBytes = try adding(
            installedAssetBytes,
            request.temporaryWorkingBytes,
            path: "storagePlan.peakRequiredDeviceBytes"
        )
        var diagnostics: [CoreAIDeviceStorageDiagnostic] = []
        if appDownloadBytes > request.appDownloadBudgetBytes {
            diagnostics.append(
                CoreAIDeviceStorageDiagnostic(
                    kind: .appDownloadBudgetExceeded,
                    message: "App-download assets exceed the author-supplied app download budget."
                )
            )
        }
        if peakRequiredDeviceBytes > request.availableDeviceBytes {
            diagnostics.append(
                CoreAIDeviceStorageDiagnostic(
                    kind: .availableStorageExceeded,
                    message: "Installed assets plus working space exceed the reported free device storage."
                )
            )
        }
        return CoreAIDeviceStoragePlan(
            appDownloadBytes: appDownloadBytes,
            onDemandDownloadBytes: onDemandDownloadBytes,
            installedAssetBytes: installedAssetBytes,
            peakRequiredDeviceBytes: peakRequiredDeviceBytes,
            diagnostics: diagnostics
        )
    }

    private static func adding(
        _ lhs: UInt64,
        _ rhs: UInt64,
        path: String
    ) throws -> UInt64 {
        let sum = lhs.addingReportingOverflow(rhs)
        guard !sum.overflow else {
            throw CoreAIDeviceEvidenceError.arithmeticOverflow(path: path)
        }
        return sum.partialValue
    }
}
