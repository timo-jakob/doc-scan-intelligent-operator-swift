import Foundation

/// Factory protocol for creating DocumentDetectors with different model configurations
public protocol DocumentDetectorFactory {
    func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector
}

/// Default factory that creates real DocumentDetectors
public struct DefaultDocumentDetectorFactory: DocumentDetectorFactory {
    public init() {}

    public func makeDetector(config: Configuration, documentType: DocumentType) async throws -> DocumentDetector {
        DocumentDetector(config: config, documentType: documentType)
    }
}

/// Core benchmark orchestration engine
public class BenchmarkEngine {
    private let configuration: Configuration
    private let documentType: DocumentType
    private let verbose: Bool
    private let detectorFactory: DocumentDetectorFactory

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

        var documentResults: [DocumentResult] = []
        for (pdfPath, isPositive) in allPDFs {
            if skipPaths.contains(pdfPath) {
                let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
                let truth = try GroundTruth.load(from: sidecarPath)
                let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
                if verbose {
                    print("Reusing existing sidecar: \(filename).json")
                }
                documentResults.append(DocumentResult(
                    filename: filename,
                    isPositiveSample: isPositive,
                    predictedIsMatch: truth.isMatch,
                    documentScore: 2
                ))
            } else {
                let result = await processInitialDocument(pdfPath: pdfPath, isPositive: isPositive)
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

    private func processInitialDocument(pdfPath: String, isPositive: Bool) async -> DocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        if verbose {
            print("Processing: \(filename)")
        }

        do {
            let detector = try await detectorFactory.makeDetector(
                config: configuration, documentType: documentType
            )
            let categorization = try await detector.categorize(pdfPath: pdfPath)
            let isMatch = categorization.agreedIsMatch ?? categorization.vlmResult.isMatch

            let sidecar = try await buildGroundTruth(
                detector: detector, isMatch: isMatch, isPositive: isPositive
            )
            let sidecarPath = GroundTruth.sidecarPath(for: pdfPath)
            try sidecar.save(to: sidecarPath)

            return DocumentResult(
                filename: filename,
                isPositiveSample: isPositive,
                predictedIsMatch: isMatch,
                documentScore: (isPositive == isMatch) ? 2 : 0
            )
        } catch {
            if verbose {
                print("Error processing \(filename): \(error.localizedDescription)")
            }
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

    // MARK: - Benchmark a Model Pair

    /// Benchmark a specific model pair against verified ground truths
    public func benchmarkModelPair(
        _ pair: ModelPair,
        pdfPaths: [String],
        groundTruths: [String: GroundTruth],
        timeoutSeconds: TimeInterval = 30
    ) async throws -> ModelPairResult {
        if let memoryDQ = checkMemory(for: pair) {
            return memoryDQ
        }

        var pairConfig = configuration
        pairConfig.modelName = pair.vlmModelName
        pairConfig.textModelName = pair.textModelName

        var documentResults: [DocumentResult] = []

        for pdfPath in pdfPaths {
            let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
            guard let truth = groundTruths[pdfPath] else { continue }

            do {
                let result = try await runWithTimeout(seconds: timeoutSeconds) {
                    try await self.processSingleDocument(
                        pdfPath: pdfPath,
                        config: pairConfig,
                        groundTruth: truth
                    )
                }
                documentResults.append(result)
            } catch is TimeoutError {
                return ModelPairResult(
                    vlmModelName: pair.vlmModelName,
                    textModelName: pair.textModelName,
                    metrics: BenchmarkMetrics.compute(from: documentResults),
                    documentResults: documentResults,
                    isDisqualified: true,
                    disqualificationReason: "Exceeded \(Int(timeoutSeconds))s timeout on \(filename)"
                )
            } catch {
                if verbose {
                    print("Error on \(filename): \(error.localizedDescription)")
                }
                documentResults.append(DocumentResult(
                    filename: filename,
                    isPositiveSample: truth.isMatch,
                    predictedIsMatch: false,
                    documentScore: 0
                ))
            }
        }

        let metrics = BenchmarkMetrics.compute(from: documentResults)
        return ModelPairResult(
            vlmModelName: pair.vlmModelName,
            textModelName: pair.textModelName,
            metrics: metrics,
            documentResults: documentResults
        )
    }
}

// MARK: - Private Helpers

private extension BenchmarkEngine {
    /// Pre-flight memory check — returns a disqualified result if the pair would exhaust memory
    func checkMemory(for pair: ModelPair) -> ModelPairResult? {
        let estimatedMB = Self.estimateMemoryMB(vlm: pair.vlmModelName, text: pair.textModelName)
        let availableMB = Self.availableMemoryMB()
        guard estimatedMB > 0, availableMB > 0, estimatedMB > availableMB else {
            return nil
        }
        if verbose {
            print("Skipping \(pair.vlmModelName) + \(pair.textModelName): "
                + "needs ~\(estimatedMB) MB, only \(availableMB) MB available")
        }
        return ModelPairResult(
            vlmModelName: pair.vlmModelName,
            textModelName: pair.textModelName,
            metrics: BenchmarkMetrics.compute(from: []),
            documentResults: [],
            isDisqualified: true,
            disqualificationReason: "Insufficient memory (~\(estimatedMB) MB needed, \(availableMB) MB available)"
        )
    }

    func processSingleDocument(
        pdfPath: String,
        config: Configuration,
        groundTruth: GroundTruth
    ) async throws -> DocumentResult {
        let filename = URL(fileURLWithPath: pdfPath).lastPathComponent
        let detector = try await detectorFactory.makeDetector(
            config: config, documentType: documentType
        )
        let categorization = try await detector.categorize(pdfPath: pdfPath)
        let isMatch = categorization.agreedIsMatch ?? categorization.vlmResult.isMatch

        var actualDate: String?
        var actualSecondaryField: String?
        var actualPatientName: String?

        if isMatch {
            let extraction = try await detector.extractData()
            if let extractedDate = extraction.date {
                actualDate = DateUtils.formatDate(extractedDate)
            }
            actualSecondaryField = extraction.secondaryField
            actualPatientName = extraction.patientName
        }

        let scoring = FuzzyMatcher.scoreDocument(
            expected: groundTruth,
            actualIsMatch: isMatch,
            actualDate: actualDate,
            actualSecondaryField: actualSecondaryField,
            actualPatientName: actualPatientName
        )

        return DocumentResult(
            filename: filename,
            isPositiveSample: groundTruth.isMatch,
            predictedIsMatch: isMatch,
            documentScore: scoring.score
        )
    }

    func runWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                let nanoseconds = UInt64(seconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: nanoseconds)
                throw TimeoutError()
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}
