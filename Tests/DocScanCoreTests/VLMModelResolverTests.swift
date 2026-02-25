@testable import DocScanCore
import XCTest

final class VLMModelResolverTests: XCTestCase {
    // MARK: - isConcreteModel: true cases

    func testConcreteModelWithOrgAndRepo() {
        XCTAssertTrue(VLMModelResolver.isConcreteModel("mlx-community/Qwen2-VL-2B-Instruct-4bit"))
    }

    func testConcreteModelMinimal() {
        XCTAssertTrue(VLMModelResolver.isConcreteModel("a/b"))
    }

    func testConcreteModelWithDots() {
        XCTAssertTrue(VLMModelResolver.isConcreteModel("org/Qwen2.5-7B-Instruct-4bit"))
    }

    // MARK: - isConcreteModel: false cases

    func testFamilyNameWithoutSlash() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("Qwen3-VL"))
    }

    func testFamilyNameFastVLM() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("FastVLM"))
    }

    func testEmptyString() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel(""))
    }

    func testWhitespaceOnly() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("   "))
    }

    // MARK: - isConcreteModel: edge cases (invalid model IDs)

    func testBareSlashIsNotConcrete() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("/"))
    }

    func testTrailingSlashIsNotConcrete() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("mlx-community/"))
    }

    func testLeadingSlashIsNotConcrete() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("/Qwen2-VL-2B"))
    }

    func testMultipleSlashesIsNotConcrete() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("org/sub/model"))
    }

    func testFilePathIsNotConcrete() {
        XCTAssertFalse(VLMModelResolver.isConcreteModel("/Users/timo/models/my-model"))
    }

    // MARK: - resolveImmediate

    func testResolveImmediateReturnsArrayForConcreteModel() {
        let result = VLMModelResolver.resolveImmediate("mlx-community/Qwen2-VL-2B-Instruct-4bit")
        XCTAssertEqual(result, ["mlx-community/Qwen2-VL-2B-Instruct-4bit"])
    }

    func testResolveImmediateReturnsNilForFamilyName() {
        XCTAssertNil(VLMModelResolver.resolveImmediate("Qwen3-VL"))
    }

    func testResolveImmediatePreservesModelId() {
        let modelId = "org/Model-7B-Instruct-4bit"
        let result = VLMModelResolver.resolveImmediate(modelId)
        XCTAssertEqual(result?.first, modelId)
    }

    func testResolveImmediateReturnsNilForInvalidSlash() {
        XCTAssertNil(VLMModelResolver.resolveImmediate("/"))
        XCTAssertNil(VLMModelResolver.resolveImmediate("org/"))
        XCTAssertNil(VLMModelResolver.resolveImmediate("/model"))
        XCTAssertNil(VLMModelResolver.resolveImmediate("a/b/c"))
    }

    func testResolveImmediateReturnsNilForEmpty() {
        XCTAssertNil(VLMModelResolver.resolveImmediate(""))
    }
}
