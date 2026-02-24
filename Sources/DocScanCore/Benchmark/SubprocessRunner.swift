import Foundation

/// Outcome of a single benchmark worker subprocess
public enum SubprocessResult: Sendable {
    /// Worker exited 0 and produced valid output
    case success(BenchmarkWorkerOutput)

    /// Worker exited with a non-zero code or was terminated by a signal
    case crashed(exitCode: Int32, signal: Int32?)

    /// Worker exited 0 but its output file could not be decoded
    case decodingFailed(String)
}

/// Spawns `docscan benchmark-worker` subprocesses to isolate MLX model crashes
public struct SubprocessRunner: Sendable {
    public init() {
        // Intentionally empty — stateless runner
    }

    /// Resolve the absolute path to the currently running executable.
    /// This ensures the worker uses the same binary as the parent.
    public static func resolveExecutablePath() -> String {
        PathUtils.resolvePath(CommandLine.arguments[0])
    }

    /// Buffer time (seconds) added on top of per-document timeouts to account for model downloading
    /// and loading before inference begins.
    static let modelLoadingBufferSeconds: TimeInterval = 300

    /// Grace period (seconds) between SIGTERM and SIGKILL escalation for stuck processes.
    static let killEscalationSeconds: TimeInterval = 5

    /// Compute a generous overall timeout for a worker subprocess.
    ///
    /// Formula: `(inferenceTimeout × documentCount) + modelLoadingBuffer`
    static func overallTimeout(for input: BenchmarkWorkerInput) -> TimeInterval {
        let documentCount = input.positivePDFs.count + input.negativePDFs.count
        return input.timeoutSeconds * Double(documentCount) + modelLoadingBufferSeconds
    }

    /// Run a single benchmark worker in a subprocess.
    ///
    /// - Parameter input: The worker input describing what to benchmark.
    /// - Returns: A ``SubprocessResult`` indicating success, crash, or decoding failure.
    public func run(input: BenchmarkWorkerInput) async throws -> SubprocessResult {
        let tempDir = FileManager.default.temporaryDirectory
        let inputURL = tempDir.appendingPathComponent("bw-input-\(UUID().uuidString).json")
        let outputURL = tempDir.appendingPathComponent("bw-output-\(UUID().uuidString).json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(input).write(to: inputURL)

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = makeWorkerProcess(inputPath: inputURL.path, outputPath: outputURL.path)
        let timeout = Self.overallTimeout(for: input)
        let (status, reason) = try await launchAndAwait(process, timeout: timeout)

        return interpretResult(status: status, reason: reason, outputURL: outputURL)
    }

    // MARK: - Private Helpers

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
                // Escalate to SIGKILL if SIGTERM doesn't stop the process
                // (e.g. MLX C++ stuck in a tight loop ignoring signals)
                let pid = process.processIdentifier
                DispatchQueue.global().asyncAfter(
                    deadline: .now() + SubprocessRunner.killEscalationSeconds
                ) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

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
