@preconcurrency import Foundation // TODO: Remove when Process/DispatchWorkItem are Sendable-annotated

/// Outcome of a single benchmark worker subprocess
public enum SubprocessResult: Equatable, Sendable {
    /// Worker exited 0 and produced valid output
    case success(BenchmarkWorkerOutput)

    /// Worker exited with a non-zero code or was terminated by a signal
    case crashed(exitCode: Int32, signal: Int32?)

    /// Worker exited 0 but its output file could not be decoded
    case decodingFailed(String)
}

/// Spawns `docscan benchmark-worker` subprocesses to isolate MLX model crashes
public struct SubprocessRunner: Sendable {
    /// Dedicated temp directory for all worker handover files.
    /// Created on init, removed by ``cleanup()``.
    let workDir: URL

    public init() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docscan-benchmark-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        workDir = dir
    }

    /// Remove the dedicated temp directory and all handover files inside it.
    public func cleanup() {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Resolve the absolute path to the currently running executable.
    /// This ensures the worker uses the same binary as the parent.
    ///
    /// Uses the **actual** current working directory (not `DOCSCAN_ORIGINAL_PWD`)
    /// because `argv[0]` is relative to the real CWD set by the wrapper script,
    /// not the user's original directory.
    public static func resolveExecutablePath() -> String {
        let arg0 = CommandLine.arguments[0]

        if arg0.hasPrefix("/") {
            return URL(fileURLWithPath: arg0).standardized.resolvingSymlinksInPath().path
        }

        // Resolve relative to the real CWD (ignoring DOCSCAN_ORIGINAL_PWD)
        let realCwd = FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: realCwd)
            .appendingPathComponent(arg0)
            .standardized
            .resolvingSymlinksInPath()
            .path
    }

    /// Buffer time (seconds) added on top of per-document timeouts to account for model downloading
    /// and loading before inference begins. Kept modest because per-inference hard timeouts now
    /// prevent individual calls from hanging indefinitely.
    static let modelLoadingBufferSeconds: TimeInterval = 120

    /// Grace period (seconds) between SIGTERM and SIGKILL escalation for stuck processes.
    static let killEscalationSeconds: TimeInterval = 5

    /// Compute a generous overall timeout for a worker subprocess.
    ///
    /// Formula: `(inferenceTimeout × documentCount) + modelLoadingBuffer`
    static func overallTimeout(for input: BenchmarkWorkerInput) -> TimeInterval {
        input.timeoutSeconds * Double(input.pdfSet.count) + modelLoadingBufferSeconds
    }

    /// Run a single benchmark worker in a subprocess.
    ///
    /// - Parameter input: The worker input describing what to benchmark.
    /// - Returns: A ``SubprocessResult`` indicating success, crash, or decoding failure.
    public func run(input: BenchmarkWorkerInput) async throws -> SubprocessResult {
        let id = UUID().uuidString
        let inputURL = workDir.appendingPathComponent("bw-input-\(id).json")
        let outputURL = workDir.appendingPathComponent("bw-output-\(id).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(input).write(to: inputURL)

        let process = makeWorkerProcess(inputPath: inputURL.path, outputPath: outputURL.path)
        let timeout = Self.overallTimeout(for: input)
        let (status, reason) = try await launchAndAwait(process, timeout: timeout)

        return interpretResult(status: status, reason: reason, outputURL: outputURL)
    }

    // MARK: - Private Helpers

    /// Escalate to SIGKILL if SIGTERM doesn't stop the process
    /// (e.g. MLX C++ stuck in a tight loop ignoring signals).
    private static func escalateToKill(_ process: Process) {
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(
            deadline: .now() + killEscalationSeconds
        ) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    private func makeWorkerProcess(inputPath: String, outputPath: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.resolveExecutablePath())
        process.arguments = [
            "benchmark-worker",
            "--input", inputPath,
            "--output", outputPath,
        ]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        return process
    }

    /// Set up termination handler + watchdog before launching so that even an
    /// instant crash (e.g. fatalError during MLX init) is captured reliably.
    private typealias TermResult = (Int32, Process.TerminationReason)

    private func launchAndAwait(
        _ process: Process, timeout: TimeInterval
    ) async throws -> TermResult {
        try await withCheckedThrowingContinuation { continuation in
            let watchdog = DispatchWorkItem { [process] in
                guard process.isRunning else { return }
                process.terminate()
                Self.escalateToKill(process)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

            // Ordering guarantee: the watchdog calls process.terminate(), which
            // triggers the terminationHandler. Since terminate() on an already-
            // terminated process is a no-op, at most one path resumes the continuation.
            process.terminationHandler = { proc in
                watchdog.cancel()
                continuation.resume(
                    returning: (proc.terminationStatus, proc.terminationReason)
                )
            }

            do {
                try process.run()
            } catch {
                watchdog.cancel()
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func interpretResult(
        status: Int32, reason: Process.TerminationReason, outputURL: URL
    ) -> SubprocessResult {
        if reason == .uncaughtSignal {
            return .crashed(exitCode: -1, signal: status)
        }
        if status != 0 {
            return .crashed(exitCode: status, signal: nil)
        }

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return .decodingFailed("Worker exited 0 but output file not found")
        }

        do {
            let outputData = try Data(contentsOf: outputURL)
            let output = try JSONDecoder().decode(BenchmarkWorkerOutput.self, from: outputData)
            return .success(output)
        } catch {
            return .decodingFailed("Failed to decode worker output: \(error.localizedDescription)")
        }
    }
}
