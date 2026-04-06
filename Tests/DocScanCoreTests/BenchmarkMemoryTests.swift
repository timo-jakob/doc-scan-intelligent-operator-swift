@testable import DocScanCore
import XCTest

/// Tests for BenchmarkEngine memory estimation and parameter parsing.
final class BenchmarkMemoryTests: XCTestCase {
    // MARK: - parseParamBillions

    func testParse7B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "Qwen2-VL-7B-Instruct-4bit"), 7.0)
    }

    func testParse2B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "Qwen2-VL-2B-Instruct-4bit"), 2.0)
    }

    func testParse0_5B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "model-0.5B-variant"), 0.5)
    }

    func testParse72B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "Qwen2-VL-72B-Instruct"), 72.0)
    }

    func testParseLowercaseB() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "starcoder2-7b-4bit"), 7.0)
    }

    func testParseNoMatch() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "some-model-without-size"), 0.0)
    }

    func testParseEmptyString() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: ""), 0.0)
    }

    func testParse14B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "Qwen2.5-14B-Instruct-4bit"), 14.0)
    }

    func testParse1_5B() {
        XCTAssertEqual(BenchmarkEngine.parseParamBillions(from: "Qwen2.5-1.5B-Instruct-4bit"), 1.5)
    }

    func testParseWithCommunityPrefix() {
        XCTAssertEqual(
            BenchmarkEngine.parseParamBillions(from: "mlx-community/Meta-Llama-3.1-8B-Instruct-4bit"),
            8.0
        )
    }

    // MARK: - estimateMemoryMB

    func testEstimateMemoryBothModels() {
        let mb = BenchmarkEngine.estimateMemoryMB(vlm: "Qwen2-VL-2B-Instruct-4bit", text: "Qwen2.5-7B-Instruct-4bit")
        // (2 + 7) * 0.5 * 1.2 * 1_000_000_000 / 1_000_000 ≈ 5399 MB (floating-point rounding)
        XCTAssertEqual(mb, 5399)
    }

    func testEstimateMemoryVLMOnly() {
        let mb = BenchmarkEngine.estimateMemoryMB(vlm: "Qwen2-VL-7B-Instruct-4bit", text: "unknown-model")
        // 7 * 0.5 * 1.2 * 1_000_000_000 / 1_000_000 = 4200 MB
        XCTAssertEqual(mb, 4200)
    }

    func testEstimateMemoryNoRecognizableSize() {
        let mb = BenchmarkEngine.estimateMemoryMB(vlm: "unknown", text: "also-unknown")
        XCTAssertEqual(mb, 0)
    }

    func testEstimateMemoryLargeModels() {
        let mb = BenchmarkEngine.estimateMemoryMB(vlm: "Qwen2-VL-72B-Instruct", text: "Qwen2.5-14B-Instruct-4bit")
        // (72 + 14) * 0.5 * 1.2 * 1_000_000_000 / 1_000_000 = 51600 MB
        XCTAssertEqual(mb, 51600)
    }

    // MARK: - availableMemoryMB

    func testAvailableMemoryIsPositive() {
        let available = BenchmarkEngine.availableMemoryMB()
        XCTAssertGreaterThan(available, 0)
    }

    func testAvailableMemoryIsLessThanPhysical() {
        let physical = ProcessInfo.processInfo.physicalMemory
        let available = BenchmarkEngine.availableMemoryMB()
        // Should be ~80% of physical, so strictly less than physical in MB
        let physicalMB = UInt64(Double(physical) / 1_000_000)
        XCTAssertLessThan(available, physicalMB)
    }
}
