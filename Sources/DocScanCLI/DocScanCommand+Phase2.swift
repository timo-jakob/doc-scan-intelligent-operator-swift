import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase 2

extension ScanCommand {
    func validateExtraction(
        _ extraction: ExtractionResult,
        documentType: DocumentType,
    ) throws -> Date {
        let typeName = documentType.displayName.lowercased()
        guard let date = extraction.date else {
            print("⚠️  Could not extract date from \(typeName)")
            print("   Date: ❌ Not found")
            throw ExitCode.failure
        }
        // Secondary field required for some document types (e.g., company for invoices)
        if documentType.isSecondaryFieldRequired, extraction.secondaryField == nil {
            print("⚠️  Could not extract \(documentType.secondaryFieldLabel.lowercased()) from \(typeName)")
            print("   Date: \(formatDate(date))")
            print("   \(documentType.secondaryFieldLabel): ❌ Not found")
            throw ExitCode.failure
        }
        return date
    }

    func displayExtractionResults(
        _ extraction: ExtractionResult,
        date: Date,
        documentType: DocumentType,
    ) {
        let fieldName = documentType.secondaryFieldLabel
        let fieldEmoji = documentType.secondaryFieldEmoji
        print("Extracted data:")
        print("   📅 Date: \(formatDate(date))")
        if let field = extraction.secondaryField {
            print("   \(fieldEmoji) \(fieldName): \(field)")
        } else if !documentType.isSecondaryFieldRequired {
            print("   \(fieldEmoji) \(fieldName): Not found (will be excluded from filename)")
        }
        if documentType.hasPatientField {
            if let patient = extraction.patientName {
                print("   👤 Patient: \(patient)")
            } else {
                print("   👤 Patient: Not found (will be excluded from filename)")
            }
        }
        print()
    }

    func printCompactPhase2(
        _ extraction: ExtractionResult,
        date: Date,
        documentType _: DocumentType,
    ) {
        let dateStr = formatDate(date)
        if let field = extraction.secondaryField {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr) · \(field)\n")
        } else {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr)\n")
        }
    }

    func formatDate(_ date: Date) -> String {
        DateUtils.formatDate(date)
    }
}
