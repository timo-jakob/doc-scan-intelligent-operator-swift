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

    /// Get the currently loaded TextLLM provider
    func makeTextLLMProvider() async -> (any TextLLMProviding)?

    /// Release GPU resources held by the TextLLM
    func releaseTextLLM() async
}

/// Default VLM factory that caches a single ModelManager
public actor DefaultVLMOnlyFactory: VLMOnlyFactory {
    private var cachedVLM: ModelManager?

    public init() {
        // Intentionally empty — the cached model is loaded lazily via preloadVLM
    }

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

    public init() {
        // Intentionally empty — the cached model is loaded lazily via preloadTextLLM
    }

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

    public func makeTextLLMProvider() -> (any TextLLMProviding)? {
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
    public let configuration: Configuration
    public let documentType: DocumentType

    /// Convenience accessor — always reads from `configuration.verbose` to avoid dual source of truth.
    public var verbose: Bool {
        configuration.verbose
    }

    public init(
        configuration: Configuration,
        documentType: DocumentType
    ) {
        self.configuration = configuration
        self.documentType = documentType
    }

    // MARK: - MLX Setup

    /// Set MLX memory budget to 80% of physical RAM.
    /// Call once before any model loading to give MLX a generous allocation.
    public static func configureMLXMemoryBudget() {
        Memory.memoryLimit = Int(Double(ProcessInfo.processInfo.physicalMemory) * 0.8)
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

    /// Pre-extract OCR text from all PDFs in parallel (shared across all TextLLM models)
    public func preExtractOCRTexts(positivePDFs: [String], negativePDFs: [String]) async -> [String: String] {
        let allPDFs = positivePDFs + negativePDFs
        let config = configuration
        let isVerbose = verbose

        return await withTaskGroup(of: (String, String?).self) { group in
            for pdfPath in allPDFs {
                group.addTask {
                    let filename = URL(fileURLWithPath: pdfPath).lastPathComponent

                    // Try direct text extraction first (faster, more accurate for searchable PDFs)
                    if let directText = PDFUtils.extractText(from: pdfPath, verbose: isVerbose),
                       directText.count >= PDFUtils.minimumTextLength {
                        if isVerbose {
                            print("  \(filename): direct text (\(directText.count) chars)")
                        }
                        return (pdfPath, directText)
                    }

                    // Fall back to Vision OCR
                    let ocrEngine = OCREngine(config: config)
                    do {
                        let image = try PDFUtils.pdfToImage(
                            at: pdfPath,
                            dpi: config.pdfDPI
                        )
                        let text = try ocrEngine.extractText(from: image)
                        if isVerbose {
                            print("  \(filename): OCR text (\(text.count) chars)")
                        }
                        return (pdfPath, text)
                    } catch {
                        print("  \(filename): OCR failed - \(error.localizedDescription)")
                        return (pdfPath, nil)
                    }
                }
            }

            var ocrTexts: [String: String] = [:]
            for await (path, text) in group {
                if let text { ocrTexts[path] = text }
            }
            return ocrTexts
        }
    }

    // MARK: - Ground Truth Generation

    /// Generate ground truth sidecar files for all documents.
    /// - Parameter skipExisting: When `true`, PDFs that already have a sidecar file are left untouched.
    public func generateGroundTruths(
        positivePDFs: [String],
        negativePDFs: [String],
        ocrTexts: [String: String],
        skipExisting: Bool = false
    ) async throws -> [String: GroundTruth] {
        var groundTruths: [String: GroundTruth] = [:]

        // Lazy-load TextLLM only when a positive document actually needs extraction.
        // This avoids a costly model preload when skipExisting covers all positives.
        var textLLM: (any TextLLMProviding)?

        for pdfPath in positivePDFs {
            let groundTruth = try await generatePositiveGroundTruth(
                pdfPath: pdfPath, ocrTexts: ocrTexts, textLLM: &textLLM,
                skipExisting: skipExisting
            )
            groundTruths[pdfPath] = groundTruth
        }

        for pdfPath in negativePDFs {
            let groundTruth = try generateNegativeGroundTruth(
                pdfPath: pdfPath, skipExisting: skipExisting
            )
            groundTruths[pdfPath] = groundTruth
        }

        return groundTruths
    }

    private func generatePositiveGroundTruth(
        pdfPath: String,
        ocrTexts: [String: String],
        textLLM: inout (any TextLLMProviding)?,
        skipExisting: Bool
    ) async throws -> GroundTruth {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)

        if skipExisting, FileManager.default.fileExists(atPath: sidecarPath) {
            print("  \(filename) — Keeping existing sidecar")
            return try GroundTruth.load(from: sidecarPath)
        }

        // Lazy-load TextLLM on first document that needs extraction
        if textLLM == nil {
            let manager = TextLLMManager(config: configuration)
            try await manager.preload { progress in
                print(
                    "\r  Loading TextLLM for ground truth generation (\(Int(progress * 100))%)...",
                    terminator: ""
                )
                fflush(stdout)
            }
            print(" Ready")
            textLLM = manager
        }

        print("  \(filename) — Extracting...", terminator: "")
        fflush(stdout)

        var date: String?
        var secondaryField: String?
        var patientName: String?

        if let ocrText = ocrTexts[pdfPath], let llm = textLLM {
            do {
                let extraction = try await llm.extractData(for: documentType, from: ocrText)
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

        try groundTruth.save(to: sidecarPath)
        print(" Done")
        return groundTruth
    }

    private func generateNegativeGroundTruth(
        pdfPath: String,
        skipExisting: Bool
    ) throws -> GroundTruth {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)

        if skipExisting, FileManager.default.fileExists(atPath: sidecarPath) {
            print("  \(filename) — Keeping existing sidecar")
            return try GroundTruth.load(from: sidecarPath)
        }

        print("  \(filename) — Negative sample")

        let groundTruth = GroundTruth(
            isMatch: false,
            documentType: documentType,
            metadata: makeGroundTruthMetadata()
        )

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
