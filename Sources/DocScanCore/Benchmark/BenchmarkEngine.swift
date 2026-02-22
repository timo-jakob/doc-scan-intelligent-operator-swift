import Foundation

/// Factory protocol for creating DocumentDetectors with different model configurations
public protocol DocumentDetectorFactory {
    func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector

    /// Pre-download model files to local cache so network latency is excluded from per-document timeouts
    func preloadModels(config: Configuration) async throws
}

/// Default factory that creates real DocumentDetectors
public struct DefaultDocumentDetectorFactory: DocumentDetectorFactory {
    public init() {}

    public func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector {
        DocumentDetector(config: config, documentType: documentType)
    }

    public func preloadModels(config: Configuration) async throws {
        print("    Preloading VLM...", terminator: "")
        fflush(stdout)
        let vlm = ModelManager(config: config)
        try await vlm.preload(modelName: config.modelName) { progress in
            print("\r    Preloading VLM (\(Int(progress * 100))%)...", terminator: "")
            fflush(stdout)
        }

        print(" Preloading TextLLM...", terminator: "")
        fflush(stdout)
        let textLLM = TextLLMManager(config: config)
        try await textLLM.preload { progress in
            print("\r    Preloading VLM... Preloading TextLLM (\(Int(progress * 100))%)...", terminator: "")
            fflush(stdout)
        }
        print(" Ready")
    }
}

/// Core benchmark orchestration engine
public class BenchmarkEngine {
    let configuration: Configuration
    let documentType: DocumentType
    let verbose: Bool
    let detectorFactory: DocumentDetectorFactory

    public init(
        configuration: Configuration,
        documentType: DocumentType,
        verbose: Bool = false,
        detectorFactory: DocumentDetectorFactory = DefaultDocumentDetectorFactory()
    ) {
        self.configuration = configuration
        self.documentType = documentType
        self.verbose = verbose
        self.detectorFactory = detectorFactory
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
    public func checkExistingSidecars(positiveDir: String, negativeDir: String?) throws -> [String: Bool] {
        var result: [String: Bool] = [:]
        let fileManager = FileManager.default

        let positivePDFs = try enumeratePDFs(in: positiveDir)
        for pdf in positivePDFs {
            let sidecar = GroundTruth.sidecarPath(for: pdf)
            result[pdf] = fileManager.fileExists(atPath: sidecar)
        }

        if let negDir = negativeDir {
            let negativePDFs = try enumeratePDFs(in: negDir)
            for pdf in negativePDFs {
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

    // MARK: - Initial Benchmark Run

    /// Run the initial benchmark to generate ground truth sidecar files
    /// - Parameter skipPaths: PDF paths to skip processing for; existing sidecars are reused instead
    public func runInitialBenchmark(
        positiveDir: String,
        negativeDir: String?,
        skipPaths: Set<String> = []
    ) async throws -> [ModelPairResult] {
        let positivePDFs = try enumeratePDFs(in: positiveDir)
        var allPDFs = positivePDFs.map { ($0, true) } // (path, isPositive)

        if let negDir = negativeDir {
            let negativePDFs = try enumeratePDFs(in: negDir)
            allPDFs += negativePDFs.map { ($0, false) }
        }

        let totalCount = allPDFs.count
        print("  Found \(totalCount) document(s) to process\n")

        var documentResults: [DocumentResult] = []
        for (index, (pdfPath, isPositive)) in allPDFs.enumerated() {
            let docNumber = index + 1
            let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
            if skipPaths.contains(pdfPath) {
                let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
                let truth = try GroundTruth.load(from: sidecarPath)
                print("  [\(docNumber)/\(totalCount)] \(filename) — reusing existing sidecar")
                documentResults.append(DocumentResult(
                    filename: filename,
                    isPositiveSample: isPositive,
                    predictedIsMatch: truth.isMatch,
                    documentScore: 2
                ))
            } else {
                let result = await processInitialDocument(
                    pdfPath: pdfPath, isPositive: isPositive,
                    index: docNumber, total: totalCount
                )
                documentResults.append(result)
            }
        }

        let metrics = BenchmarkMetrics.compute(from: documentResults)
        return [ModelPairResult(
            vlmModelName: configuration.modelName,
            textModelName: configuration.textModelName,
            metrics: metrics,
            documentResults: documentResults
        )]
    }

    private func processInitialDocument(
        pdfPath: String, isPositive: Bool,
        index: Int, total: Int
    ) async -> DocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        print("  [\(index)/\(total)] \(filename) — Categorizing...", terminator: "")
        fflush(stdout)

        do {
            let detector = try await detectorFactory.makeDetector(
                config: configuration, documentType: documentType
            )
            let categorization = try await detector.categorize(pdfPath: pdfPath)
            let isMatch = categorization.agreedIsMatch ?? categorization.vlmResult.isMatch

            if isMatch {
                print(" Extracting...", terminator: "")
                fflush(stdout)
            }
            let sidecar = try await buildGroundTruth(
                detector: detector, isMatch: isMatch, isPositive: isPositive
            )
            let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
            try sidecar.save(to: sidecarPath)

            print(isMatch ? " Done" : " No match")

            return DocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: isMatch,
                documentScore: (isPositive == isMatch) ? 2 : 0
            )
        } catch {
            print(" Error: \(error.localizedDescription)")
            return DocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: false,
                documentScore: 0
            )
        }
    }

    private func buildGroundTruth(
        detector: DocumentDetector, isMatch: Bool, isPositive: Bool
    ) async throws -> GroundTruth {
        var date: String?
        var secondaryField: String?
        var patientName: String?

        if isMatch {
            let extraction = try await detector.extractData()
            if let extractedDate = extraction.date {
                date = DateUtils.formatDate(extractedDate)
            }
            secondaryField = extraction.secondaryField
            patientName = extraction.patientName
        }

        return GroundTruth(
            isMatch: isPositive,
            documentType: documentType,
            date: date,
            secondaryField: secondaryField,
            patientName: patientName,
            metadata: GroundTruthMetadata(
                vlmModel: configuration.modelName,
                textModel: configuration.textModelName,
                generatedAt: Date(),
                verified: false
            )
        )
    }
}
