import ArgumentParser
import DocScanCore
import Foundation

// MARK: - Phase 2

extension ScanCommand {
    func validateExtraction(
        _ extraction: ExtractionResult,
        documentType: DocumentType
    ) throws -> Date {
        let typeName = documentType.displayName.lowercased()
        guard let date = extraction.date else {
            print("⚠️  Could not extract date from \(typeName)")
            print("   Date: ❌ Not found")
            throw ExitCode.failure
        }
        if documentType == .invoice, extraction.secondaryField == nil {
            print("⚠️  Could not extract company from invoice")
            print("   Date: \(formatDate(date))")
            print("   Company: ❌ Not found")
            throw ExitCode.failure
        }
        return date
    }

    func displayExtractionResults(
        _ extraction: ExtractionResult,
        date: Date,
        documentType: DocumentType
    ) {
        let fieldName = documentType == .invoice ? "Company" : "Doctor"
        let fieldEmoji = documentType == .invoice ? "🏢" : "👨‍⚕️"
        print("Extracted data:")
        print("   📅 Date: \(formatDate(date))")
        if let field = extraction.secondaryField {
            print("   \(fieldEmoji) \(fieldName): \(field)")
        } else if documentType == .prescription {
            print("   \(fieldEmoji) \(fieldName): Not found (will be excluded from filename)")
        }
        if documentType == .prescription {
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
        documentType _: DocumentType
    ) {
        let dateStr = formatDate(date)
        if let field = extraction.secondaryField {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr) · \(field)\n")
        } else {
            writeStdout("📄 Phase 2  ✅ extracted  \(dateStr)\n")
        }
    }

    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
