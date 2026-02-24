import Foundation
import MLX

/// Factory protocol for creating VLM providers for benchmarking
public protocol VLMOnlyFactory: Sendable {
    /// Pre-download and load a VLM model
    func preloadVLM(modelName: String, config: Configuration) async throws

    /// Get the currently loaded VLM provider
    func makeVLMProvider() async -> VLMProvider?

    /// Release GPU resources held by the VLM
    func releaseVLM() async
}

/// Factory protocol for creating TextLLM managers for benchmarking
public protocol TextLLMOnlyFactory: Sendable {
    /// Pre-download and load a TextLLM model
    func preloadTextLLM(modelName: String, config: Configuration) async throws

    /// Get the currently loaded TextLLM manager
    func makeTextLLMManager() async -> TextLLMManager?

    /// Release GPU resources held by the TextLLM
    func releaseTextLLM() async
}

/// Default VLM factory that caches a single ModelManager
public actor DefaultVLMOnlyFactory: VLMOnlyFactory {
    private var cachedVLM: ModelManager?

    public init() {}

    public func preloadVLM(modelName: String, config: Configuration) async throws {
        releaseCache()

        var vlmConfig = config
        vlmConfig.modelName = modelName
        let vlm = ModelManager(config: vlmConfig)
        try await vlm.preload(modelName: modelName) { progress in
            print("\r    Preloading VLM (\(Int(progress * 100))%)...", terminator: "")
            fflush(stdout)
        }
        print(" Ready")
        cachedVLM = vlm
    }

    public func makeVLMProvider() -> VLMProvider? {
        cachedVLM
    }

    public func releaseVLM() {
        releaseCache()
        Memory.clearCache()
    }

    private func releaseCache() {
        cachedVLM = nil
    }
}

/// Default TextLLM factory that caches a single TextLLMManager
public actor DefaultTextLLMOnlyFactory: TextLLMOnlyFactory {
    private var cachedTextLLM: TextLLMManager?

    public init() {}

    public func preloadTextLLM(modelName: String, config: Configuration) async throws {
        releaseCache()

        var textConfig = config
        textConfig.textModelName = modelName
        let textLLM = TextLLMManager(config: textConfig)
        try await textLLM.preload { progress in
            print("\r    Preloading TextLLM (\(Int(progress * 100))%)...", terminator: "")
            fflush(stdout)
        }
        print(" Ready")
        cachedTextLLM = textLLM
    }

    public func makeTextLLMManager() -> TextLLMManager? {
        cachedTextLLM
    }

    public func releaseTextLLM() {
        releaseCache()
        Memory.clearCache()
    }

    private func releaseCache() {
        cachedTextLLM = nil
    }
}

/// Core benchmark orchestration engine
public final class BenchmarkEngine: Sendable {
    let configuration: Configuration
    let documentType: DocumentType
    let verbose: Bool

    public init(
        configuration: Configuration,
        documentType: DocumentType,
        verbose: Bool = false
    ) {
        self.configuration = configuration
        self.documentType = documentType
        self.verbose = verbose
    }

    // MARK: - PDF Enumeration

    /// Enumerate PDF files in a directory
    public func enumeratePDFs(in directory: String) throws -> [String] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory) else {
            throw DocScanError.fileNotFound(directory)
        }

        let contents = try fileManager.contentsOfDirectory(atPath: directory)
        return contents
            .filter { $0.lowercased().hasSuffix(".pdf") }
            .sorted()
            .map { (directory as NSString).appendingPathComponent($0) }
    }

    // MARK: - Sidecar Management

    /// Check which PDFs already have sidecar files
    public func checkExistingSidecars(positiveDir: String, negativeDir: String) throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        let fileManager = FileManager.default

        for dir in [positiveDir, negativeDir] {
            let pdfs = try enumeratePDFs(in: dir)
            for pdf in pdfs {
                let sidecar = GroundTruth.sidecarPath(for: pdf)
                result[pdf] = fileManager.fileExists(atPath: sidecar)
            }
        }

        return result
    }

    /// Load all ground truth sidecar files for given PDF paths
    public func loadGroundTruths(pdfPaths: [String]) throws -> [String: GroundTruth] {
        var groundTruths: [String: GroundTruth] = [:]

        for pdfPath in pdfPaths {
            let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
            guard FileManager.default.fileExists(atPath: sidecarPath) else {
                throw DocScanError.benchmarkError(
                    "Missing ground truth sidecar for: \(URL(fileURLWithPath: pdfPath).lastPathComponent)"
                )
            }
            groundTruths[pdfPath] = try GroundTruth.load(from: sidecarPath)
        }

        return groundTruths
    }

    // MARK: - OCR Pre-extraction

    /// Pre-extract OCR text from all PDFs (shared across all TextLLM models)
    public func preExtractOCRTexts(positivePDFs: [String], negativePDFs: [String]) async -> [String: String] {
        var ocrTexts: [String: String] = [:]
        let allPDFs = positivePDFs + negativePDFs
        let ocrEngine = OCREngine(config: configuration)

        for pdfPath in allPDFs {
            let filename = URL(fileURLWithPath: pdfPath).lastPathComponent

            // Try direct text extraction first (faster, more accurate for searchable PDFs)
            if let directText = PDFUtils.extractText(from: pdfPath, verbose: verbose),
               directText.count >= PDFUtils.minimumTextLength {
                ocrTexts[pdfPath] = directText
                if verbose {
                    print("  \(filename): direct text (\(directText.count) chars)")
                }
                continue
            }

            // Fall back to Vision OCR
            do {
                let image = try PDFUtils.pdfToImage(
                    at: pdfPath,
                    dpi: configuration.pdfDPI
                )
                let text = try await ocrEngine.extractText(from: image)
                ocrTexts[pdfPath] = text
                if verbose {
                    print("  \(filename): OCR text (\(text.count) chars)")
                }
            } catch {
                print("  \(filename): OCR failed - \(error.localizedDescription)")
            }
        }

        return ocrTexts
    }

    // MARK: - Ground Truth Generation

    /// Generate ground truth sidecar files for all documents
    public func generateGroundTruths(
        positivePDFs: [String],
        negativePDFs: [String],
        ocrTexts: [String: String]
    ) async throws -> [String: GroundTruth] {
        var groundTruths: [String: GroundTruth] = [:]
        let textLLM = TextLLMManager(config: configuration)
        try await textLLM.preload { progress in
            print("\r  Loading TextLLM for ground truth generation (\(Int(progress * 100))%)...", terminator: "")
            fflush(stdout)
        }
        print(" Ready")

        for pdfPath in positivePDFs {
            let groundTruth = try await generatePositiveGroundTruth(
                pdfPath: pdfPath, ocrTexts: ocrTexts, textLLM: textLLM
            )
            groundTruths[pdfPath] = groundTruth
        }

        for pdfPath in negativePDFs {
            let groundTruth = try generateNegativeGroundTruth(pdfPath: pdfPath)
            groundTruths[pdfPath] = groundTruth
        }

        return groundTruths
    }

    private func generatePositiveGroundTruth(
        pdfPath: String,
        ocrTexts: [String: String],
        textLLM: TextLLMManager
    ) async throws -> GroundTruth {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        print("  \(filename) — Extracting...", terminator: "")
        fflush(stdout)

        var date: String?
        var secondaryField: String?
        var patientName: String?

        if let ocrText = ocrTexts[pdfPath] {
            do {
                let extraction = try await textLLM.extractData(for: documentType, from: ocrText)
                if let extractedDate = extraction.date {
                    date = DateUtils.formatDate(extractedDate)
                }
                secondaryField = extraction.secondaryField
                patientName = extraction.patientName
            } catch {
                print(" Error: \(error.localizedDescription)")
            }
        }

        let groundTruth = GroundTruth(
            isMatch: true,
            documentType: documentType,
            date: date,
            secondaryField: secondaryField,
            patientName: patientName,
            metadata: makeGroundTruthMetadata()
        )

        let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
        try groundTruth.save(to: sidecarPath)
        print(" Done")
        return groundTruth
    }

    private func generateNegativeGroundTruth(pdfPath: String) throws -> GroundTruth {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        print("  \(filename) — Negative sample")

        let groundTruth = GroundTruth(
            isMatch: false,
            documentType: documentType,
            metadata: makeGroundTruthMetadata()
        )

        let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
        try groundTruth.save(to: sidecarPath)
        return groundTruth
    }

    private func makeGroundTruthMetadata() -> GroundTruthMetadata {
        GroundTruthMetadata(
            vlmModel: configuration.modelName,
            textModel: configuration.textModelName,
            generatedAt: Date(),
            verified: false
        )
    }
}
