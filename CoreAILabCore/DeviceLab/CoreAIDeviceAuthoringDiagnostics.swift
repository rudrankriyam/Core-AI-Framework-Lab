import Foundation

enum CoreAIDeviceAuthoringDiagnostics {
    static func evaluate(
        shapeRequest: CoreAIDeviceShapeAuthoringRequest,
        preferredComputeUnit: CoreAIComputeUnitPreference,
        expectation: CoreAIDeviceEvidenceExpectation,
        evidence: CoreAIDeviceTrialEvidence?
    ) -> [CoreAIDeviceDiagnostic] {
        shapeDiagnostics(for: shapeRequest)
            + compatibilityDiagnostics(
                shapeRequest: shapeRequest,
                preferredComputeUnit: preferredComputeUnit,
                expectation: expectation,
                evidence: evidence
            )
    }

    private static func shapeDiagnostics(
        for request: CoreAIDeviceShapeAuthoringRequest
    ) -> [CoreAIDeviceDiagnostic] {
        var diagnostics: [CoreAIDeviceDiagnostic] = []
        if let context = request.requestedContextTokens {
            if context <= 0 {
                diagnostics.append(
                    diagnostic(
                        id: "context.nonpositive",
                        severity: .error,
                        category: .context,
                        title: "Context must be positive",
                        detail: "Enter a context length greater than zero."
                    )
                )
            } else if context > CoreAIDeviceShapeLimits.maximumContextTokens {
                diagnostics.append(
                    diagnostic(
                        id: "context.safety-ceiling",
                        severity: .error,
                        category: .context,
                        title: "Context exceeds the safety ceiling",
                        detail: "Device Lab bounds authored context at \(CoreAIDeviceShapeLimits.maximumContextTokens) tokens."
                    )
                )
            } else if let maximum = request.maximumContextTokens,
                      context > maximum {
                diagnostics.append(
                    diagnostic(
                        id: "context.exceeds-maximum",
                        severity: .error,
                        category: .context,
                        title: "Context exceeds the authored limit",
                        detail: "The requested context is \(context) tokens, but the declared limit is \(maximum)."
                    )
                )
            }
        }
        if let maximum = request.maximumContextTokens {
            if maximum <= 0 {
                diagnostics.append(
                    diagnostic(
                        id: "context.maximum-nonpositive",
                        severity: .error,
                        category: .context,
                        title: "Context limit must be positive",
                        detail: "The authored maximum context must be greater than zero."
                    )
                )
            } else if maximum > CoreAIDeviceShapeLimits.maximumContextTokens {
                diagnostics.append(
                    diagnostic(
                        id: "context.maximum-safety-ceiling",
                        severity: .error,
                        category: .context,
                        title: "Context limit exceeds the safety ceiling",
                        detail: "The maximum authored context is \(CoreAIDeviceShapeLimits.maximumContextTokens) tokens."
                    )
                )
            }
        }

        if request.shapes.isEmpty {
            diagnostics.append(
                diagnostic(
                    id: "shape.missing",
                    severity: .warning,
                    category: .shape,
                    title: "No iPhone shape profile",
                    detail: "Add the input shapes exercised by the intended device trial."
                )
            )
        }
        if request.shapes.count > CoreAIDeviceShapeLimits.maximumShapeCount {
            diagnostics.append(
                diagnostic(
                    id: "shape.count-limit",
                    severity: .error,
                    category: .shape,
                    title: "Too many input shapes",
                    detail: "A device profile supports at most \(CoreAIDeviceShapeLimits.maximumShapeCount) shapes."
                )
            )
        }

        var identifiers = Set<String>()
        var totalElements = 0
        var reportedTotalLimit = false
        for (shapeIndex, shape) in request.shapes.prefix(
            CoreAIDeviceShapeLimits.maximumShapeCount
        ).enumerated() {
            let trimmedIdentifier = shape.id.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let diagnosticIdentifier = trimmedIdentifier.isEmpty
                ? "unnamed-\(shapeIndex)"
                : shape.id
            if trimmedIdentifier.isEmpty {
                diagnostics.append(
                    diagnostic(
                        id: "shape.\(diagnosticIdentifier).unnamed",
                        severity: .error,
                        category: .shape,
                        title: "Shape needs a name",
                        detail: "Every input shape must identify its runtime input."
                    )
                )
            }
            if !identifiers.insert(shape.id).inserted {
                diagnostics.append(
                    diagnostic(
                        id: "shape.\(diagnosticIdentifier).duplicate",
                        severity: .error,
                        category: .shape,
                        title: "Shape name is duplicated",
                        detail: "Every input shape needs a unique name."
                    )
                )
            }
            if shape.dimensions.isEmpty {
                diagnostics.append(
                    diagnostic(
                        id: "shape.\(diagnosticIdentifier).empty",
                        severity: .error,
                        category: .shape,
                        title: "Shape has no dimensions",
                        detail: "A static shape must include at least one dimension."
                    )
                )
                continue
            }
            if shape.dimensions.count > CoreAIDeviceShapeLimits.maximumRank {
                diagnostics.append(
                    diagnostic(
                        id: "shape.\(diagnosticIdentifier).rank-limit",
                        severity: .error,
                        category: .shape,
                        title: "Shape rank exceeds the safety ceiling",
                        detail: "A device shape supports at most \(CoreAIDeviceShapeLimits.maximumRank) dimensions."
                    )
                )
                continue
            }
            if shape.dimensions.contains(where: { $0 == nil }) {
                diagnostics.append(
                    diagnostic(
                        id: "shape.\(diagnosticIdentifier).dynamic",
                        severity: .warning,
                        category: .shape,
                        title: "Dynamic dimension needs a device variant",
                        detail: request.expectsFrequentReshapes
                            ? "Author and benchmark concrete iPhone shapes even when frequent reshapes are expected."
                            : "The target does not expect frequent reshapes; replace dynamic dimensions with a tested static profile."
                    )
                )
            }
            var elementCount = 1
            var hasCountableStaticShape = true
            for (index, dimension) in shape.dimensions.enumerated() {
                guard let dimension else {
                    hasCountableStaticShape = false
                    continue
                }
                if dimension <= 0 {
                    diagnostics.append(
                        diagnostic(
                            id: "shape.\(diagnosticIdentifier).dimension.\(index).nonpositive",
                            severity: .error,
                            category: .shape,
                            title: "Shape dimension must be positive",
                            detail: "Dimension \(index + 1) of \(shape.id) is \(dimension)."
                        )
                    )
                    hasCountableStaticShape = false
                    continue
                }
                if dimension > CoreAIDeviceShapeLimits.maximumDimension {
                    diagnostics.append(
                        diagnostic(
                            id: "shape.\(diagnosticIdentifier).dimension.\(index).limit",
                            severity: .error,
                            category: .shape,
                            title: "Shape dimension exceeds the safety ceiling",
                            detail: "Each dimension is bounded at \(CoreAIDeviceShapeLimits.maximumDimension)."
                        )
                    )
                    hasCountableStaticShape = false
                    continue
                }
                let product = elementCount.multipliedReportingOverflow(by: dimension)
                if product.overflow {
                    diagnostics.append(
                        diagnostic(
                            id: "shape.\(diagnosticIdentifier).overflow",
                            severity: .error,
                            category: .shape,
                            title: "Shape is too large to size safely",
                            detail: "The element count overflows the supported integer range."
                        )
                    )
                    hasCountableStaticShape = false
                    break
                }
                if product.partialValue
                    > CoreAIDeviceShapeLimits.maximumElementsPerShape {
                    diagnostics.append(
                        diagnostic(
                            id: "shape.\(diagnosticIdentifier).element-limit",
                            severity: .error,
                            category: .shape,
                            title: "Shape exceeds the element safety ceiling",
                            detail: "One shape is bounded at \(CoreAIDeviceShapeLimits.maximumElementsPerShape) elements."
                        )
                    )
                    hasCountableStaticShape = false
                    break
                }
                elementCount = product.partialValue
            }
            guard hasCountableStaticShape else { continue }
            let total = totalElements.addingReportingOverflow(elementCount)
            if total.overflow
                || total.partialValue
                    > CoreAIDeviceShapeLimits.maximumTotalElements {
                if !reportedTotalLimit {
                    diagnostics.append(
                        diagnostic(
                            id: "shape.total-element-limit",
                            severity: .error,
                            category: .shape,
                            title: "Profile exceeds the total element ceiling",
                            detail: "All static shapes together are bounded at \(CoreAIDeviceShapeLimits.maximumTotalElements) elements."
                        )
                    )
                    reportedTotalLimit = true
                }
            } else {
                totalElements = total.partialValue
            }
        }
        return diagnostics
    }

    private static func compatibilityDiagnostics(
        shapeRequest: CoreAIDeviceShapeAuthoringRequest,
        preferredComputeUnit: CoreAIComputeUnitPreference,
        expectation: CoreAIDeviceEvidenceExpectation,
        evidence: CoreAIDeviceTrialEvidence?
    ) -> [CoreAIDeviceDiagnostic] {
        guard let evidence else {
            return [
                diagnostic(
                    id: "compatibility.missing-evidence",
                    severity: .warning,
                    category: .specialization,
                    title: "Device compatibility is not proven",
                    detail: "Import evidence from a physical runner before making an iPhone compatibility claim."
                ),
                placementDiagnostic(
                    preferredComputeUnit: preferredComputeUnit,
                    placement: .unavailable
                ),
            ]
        }
        guard (try? expectation.validate()) != nil,
              expectation.matches(evidence) else {
            return [
                diagnostic(
                    id: "compatibility.identity-mismatch",
                    severity: .error,
                    category: .specialization,
                    title: "Evidence identity does not match",
                    detail: "Artifact SHA-256, byte count, configuration identifier, and configuration SHA-256 must match the selected trial contract exactly."
                ),
                placementDiagnostic(
                    preferredComputeUnit: preferredComputeUnit,
                    placement: .unavailable
                ),
            ]
        }
        guard evidenceMatchesAuthoring(
            evidence,
            request: shapeRequest,
            preferredComputeUnit: preferredComputeUnit
        ) else {
            return [
                diagnostic(
                    id: "compatibility.evidence-mismatch",
                    severity: .warning,
                    category: .specialization,
                    title: "Imported evidence belongs to another configuration",
                    detail: "Compute preference, reshape policy, context, and static input shapes must exactly match before compatibility results apply."
                ),
                placementDiagnostic(
                    preferredComputeUnit: preferredComputeUnit,
                    placement: .unavailable
                ),
            ]
        }

        var diagnostics = evidence.neuralEngineCompatibilityChecks.map { check in
            switch check.result {
            case .passed:
                diagnostic(
                    id: "compatibility.\(check.category.rawValue).passed",
                    severity: .information,
                    category: check.category.diagnosticCategory,
                    title: "\(check.category.title) check passed",
                    detail: check.detail
                )
            case .failed:
                diagnostic(
                    id: "compatibility.\(check.category.rawValue).failed",
                    severity: .error,
                    category: check.category.diagnosticCategory,
                    title: "\(check.category.title) check failed",
                    detail: check.detail
                )
            case .notEvaluated:
                diagnostic(
                    id: "compatibility.\(check.category.rawValue).not-evaluated",
                    severity: .warning,
                    category: check.category.diagnosticCategory,
                    title: "\(check.category.title) was not evaluated",
                    detail: check.detail
                )
            }
        }
        diagnostics.append(
            outcomeDiagnostic(
                name: "Specialization",
                category: .specialization,
                outcome: evidence.specialization
            )
        )
        diagnostics.append(
            outcomeDiagnostic(
                name: "Inference",
                category: .inference,
                outcome: evidence.inference
            )
        )
        diagnostics.append(
            placementDiagnostic(
                preferredComputeUnit: preferredComputeUnit,
                placement: evidence.placement
            )
        )
        return diagnostics
    }

    private static func evidenceMatchesAuthoring(
        _ evidence: CoreAIDeviceTrialEvidence,
        request: CoreAIDeviceShapeAuthoringRequest,
        preferredComputeUnit: CoreAIComputeUnitPreference
    ) -> Bool {
        guard let staticShapes = staticShapes(from: request) else { return false }
        return evidence.configuration.preferredComputeUnit == preferredComputeUnit
            && evidence.configuration.expectsFrequentReshapes
                == request.expectsFrequentReshapes
            && evidence.configuration.contextTokens == request.requestedContextTokens
            && evidence.configuration.staticInputShapes == staticShapes
    }

    private static func staticShapes(
        from request: CoreAIDeviceShapeAuthoringRequest
    ) -> [String: [Int]]? {
        guard request.shapes.count <= CoreAIDeviceShapeLimits.maximumShapeCount else {
            return nil
        }
        var result: [String: [Int]] = [:]
        for shape in request.shapes {
            guard result[shape.id] == nil else { return nil }
            guard shape.dimensions.count <= CoreAIDeviceShapeLimits.maximumRank else {
                return nil
            }
            var dimensions: [Int] = []
            dimensions.reserveCapacity(shape.dimensions.count)
            for dimension in shape.dimensions {
                guard let dimension else { return nil }
                dimensions.append(dimension)
            }
            result[shape.id] = dimensions
        }
        return result
    }

    private static func outcomeDiagnostic(
        name: String,
        category: CoreAIDeviceDiagnosticCategory,
        outcome: CoreAIDeviceTrialOutcome
    ) -> CoreAIDeviceDiagnostic {
        switch outcome.status {
        case .notRun:
            diagnostic(
                id: "outcome.\(category.rawValue).not-run",
                severity: .warning,
                category: category,
                title: "\(name) was not run",
                detail: outcome.detail
            )
        case .succeeded:
            diagnostic(
                id: "outcome.\(category.rawValue).succeeded",
                severity: .information,
                category: category,
                title: "\(name) passed on the recorded device",
                detail: outcome.detail
            )
        case .failed:
            diagnostic(
                id: "outcome.\(category.rawValue).failed",
                severity: .error,
                category: category,
                title: "\(name) failed on the recorded device",
                detail: outcome.detail
            )
        }
    }

    private static func placementDiagnostic(
        preferredComputeUnit: CoreAIComputeUnitPreference,
        placement: CoreAIDevicePlacementEvidence
    ) -> CoreAIDeviceDiagnostic {
        if placement.reportsNeuralEnginePlacement {
            return diagnostic(
                id: "placement.observed-neural-engine",
                severity: .information,
                category: .placement,
                title: "Imported evidence reports Neural Engine placement",
                detail: "The record names Neural Engine placement and cites \(placement.source ?? "an unspecified source")."
            )
        }
        if placement.availability == .observed {
            return diagnostic(
                id: "placement.observed-other",
                severity: .warning,
                category: .placement,
                title: "Neural Engine placement was not observed",
                detail: "Imported evidence reported \(placement.actualComputeUnits.joined(separator: ", "))."
            )
        }
        let preference = preferredComputeUnit == .neuralEngine
            ? "A Neural Engine preference"
            : "The selected compute preference"
        return diagnostic(
            id: "placement.unavailable",
            severity: .warning,
            category: .placement,
            title: "Execution placement is unavailable",
            detail: "\(preference) does not prove where Core AI executed the model. Import measurement evidence from Instruments or another explicit source."
        )
    }

    private static func diagnostic(
        id: String,
        severity: CoreAIDeviceDiagnosticSeverity,
        category: CoreAIDeviceDiagnosticCategory,
        title: String,
        detail: String
    ) -> CoreAIDeviceDiagnostic {
        CoreAIDeviceDiagnostic(
            id: id,
            severity: severity,
            category: category,
            title: title,
            detail: detail
        )
    }
}
