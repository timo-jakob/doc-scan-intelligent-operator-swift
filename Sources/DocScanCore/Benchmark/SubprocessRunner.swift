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

        // Wait for termination asynchronously
        typealias TermResult = (Int32, Process.TerminationReason)
        let (exitCode, terminationReason): TermResult = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: (proc.terminationStatus, proc.terminationReason))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }

        // Check for crash / non-zero exit
        if terminationReason == .uncaughtSignal {
            return .crashed(exitCode: exitCode, signal: exitCode)
        }
        if exitCode != 0 {
            return .crashed(exitCode: exitCode, signal: nil)
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
