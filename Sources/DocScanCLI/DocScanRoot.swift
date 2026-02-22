import ArgumentParser

@main
struct DocScanRoot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "docscan",
        abstract: "AI-powered document detection and renaming using two-phase verification",
        discussion: """
        Phase 1: Categorization (VLM + OCR in parallel) - Does this match the document type?
        Phase 2: Data Extraction (OCR + TextLLM only) - Extract date and secondary field

        Supported document types:
          invoice      - Invoices, bills, receipts (extracts: date, company)
          prescription - Doctor's prescriptions (extracts: date, doctor)

        Subcommands:
          scan (default) - Scan and rename a single PDF document
          benchmark      - Evaluate model pairs against a labeled document corpus
        """,
        version: "2.0.0",
        subcommands: [ScanCommand.self, BenchmarkCommand.self],
        defaultSubcommand: ScanCommand.self
    )
}
