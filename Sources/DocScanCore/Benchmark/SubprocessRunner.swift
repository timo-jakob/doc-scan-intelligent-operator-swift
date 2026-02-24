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
        let executablePath = Self.resolveExecutablePath()
        let tempDir = FileManager.default.temporaryDirectory

        let inputURL = tempDir.appendingPathComponent("bw-input-\(UUID().uuidString).json")
        let outputURL = tempDir.appendingPathComponent("bw-output-\(UUID().uuidString).json")

        // Write input JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let inputData = try encoder.encode(input)
        try inputData.write(to: inputURL)

        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Spawn worker
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "benchmark-worker",
            "--input", inputURL.path,
            "--output", outputURL.path,
        ]

        // Inherit stdout/stderr so the user sees preloading progress
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // Launch process — if run() throws, the process never started
        try process.run()

        let timeout = Self.overallTimeout(for: input)
        return await awaitProcess(process, outputURL: outputURL, timeout: timeout)
    }

    /// Wait for a process to finish (with timeout), then interpret the result.
    private func awaitProcess(
        _ process: Process, outputURL: URL, timeout: TimeInterval
    ) async -> SubprocessResult {
        // Wait for termination asynchronously.
        // Foundation guarantees terminationHandler fires even if the process
        // already exited before the handler was set.
        typealias TermResult = (Int32, Process.TerminationReason)
        let termination = await withCheckedContinuation { (continuation: CheckedContinuation<TermResult?, Never>) in
            // Watchdog: terminate the process if it exceeds the overall timeout
            let watchdog = DispatchWorkItem { [process] in
                if process.isRunning {
                    process.terminate()
                }
            }
            let deadline: DispatchTime = .now() + timeout
            DispatchQueue.global().asyncAfter(deadline: deadline, execute: watchdog)

            process.terminationHandler = { proc in
                watchdog.cancel()
                continuation.resume(returning: (proc.terminationStatus, proc.terminationReason))
            }
        }

        guard let (status, reason) = termination else {
            return .crashed(exitCode: -1, signal: nil)
        }

        // Check for crash / non-zero exit.
        // When terminated by a signal, terminationStatus holds the signal number.
        if reason == .uncaughtSignal {
            return .crashed(exitCode: -1, signal: status)
        }
        if status != 0 {
            return .crashed(exitCode: status, signal: nil)
        }

        // Read output JSON
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return .decodingFailed("Worker exited 0 but output file not found")
        }

        do {
            let outputData = try Data(contentsOf: outputURL)
            let decoder = JSONDecoder()
            let output = try decoder.decode(BenchmarkWorkerOutput.self, from: outputData)
            return .success(output)
        } catch {
            return .decodingFailed("Failed to decode worker output: \(error.localizedDescription)")
        }
    }
}
