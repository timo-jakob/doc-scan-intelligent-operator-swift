import Foundation

extension DocumentDetector {
    /// Generate filename from document data
    public nonisolated func generateFilename(from data: DocumentData) -> String? {
        guard data.isMatch else { return nil }
        guard let date = data.date else { return nil }

        // For invoices, company is required
        if documentType == .invoice, data.secondaryField == nil {
            return nil
        }

        let dateString = DateUtils.formatDate(date, format: config.dateFormat)

        // Use document type's default pattern
        var pattern = documentType.defaultFilenamePattern
        pattern = pattern.replacingOccurrences(of: "{date}", with: dateString)

        // Replace the secondary field placeholder based on document type
        switch documentType {
        case .invoice:
            guard let company = data.secondaryField else { return nil }
            pattern = pattern.replacingOccurrences(
                of: "{company}", with: company
            )
        case .prescription:
            pattern = applyPrescriptionPlaceholders(
                pattern: pattern, data: data
            )
        }

        return pattern
    }

    /// Apply prescription-specific placeholder replacements
    private nonisolated func applyPrescriptionPlaceholders(
        pattern: String,
        data: DocumentData
    ) -> String {
        var result = pattern

        // Handle patient name placeholder (optional)
        if let patientName = data.patientName {
            result = result.replacingOccurrences(
                of: "{patient}", with: patientName
            )
        } else {
            result = result.replacingOccurrences(
                of: "für_{patient}_", with: ""
            )
        }

        // Handle doctor name placeholder (optional)
        if let doctor = data.secondaryField {
            result = result.replacingOccurrences(
                of: "{doctor}", with: doctor
            )
        } else {
            result = result.replacingOccurrences(
                of: "_von_{doctor}", with: ""
            )
        }

        return result
    }
}
