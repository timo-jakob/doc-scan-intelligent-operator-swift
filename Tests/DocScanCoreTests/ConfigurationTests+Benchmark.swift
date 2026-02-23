@testable import DocScanCore
import XCTest

// MARK: - Benchmark Configuration Tests

extension ConfigurationTests {
    func testDefaultTextModelName() {
        let config = Configuration.defaultConfiguration
        XCTAssertEqual(config.textModelName, "mlx-community/Qwen2.5-7B-Instruct-4bit")
    }

    func testCustomTextModelName() {
        let config = Configuration(textModelName: "mlx-community/Custom-Text-Model")
        XCTAssertEqual(config.textModelName, "mlx-community/Custom-Text-Model")
    }

    func testTextModelNamePropagation() {
        let customModel = "mlx-community/Qwen2.5-3B-Instruct-4bit"
        let config = Configuration(textModelName: customModel)
        XCTAssertEqual(config.textModelName, customModel)
        XCTAssertEqual(config.modelName, "mlx-community/Qwen2-VL-2B-Instruct-4bit")
    }

    func testDefaultHuggingFaceUsernameIsNil() {
        let config = Configuration.defaultConfiguration
        XCTAssertNil(config.huggingFaceUsername)
    }

    func testCustomHuggingFaceUsername() {
        let config = Configuration(huggingFaceUsername: "my-hf-user")
        XCTAssertEqual(config.huggingFaceUsername, "my-hf-user")
    }

    func testYAMLBackwardsCompatibilityWithoutTextModelName() throws {
        let yamlContent = """
        modelName: test-model
        modelCacheDir: /test/cache
        maxTokens: 512
        temperature: 0.5
        pdfDPI: 300
        verbose: true
        output:
          dateFormat: dd-MM-yyyy
          filenamePattern: "{company}_{date}.pdf"
        """

        let configPath = tempDirectory.appendingPathComponent("legacy_config.yaml").path
        try yamlContent.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = try Configuration.load(from: configPath)

        XCTAssertEqual(config.modelName, "test-model")
        XCTAssertEqual(config.textModelName, "mlx-community/Qwen2.5-7B-Instruct-4bit")
        XCTAssertNil(config.huggingFaceUsername)
    }

    func testYAMLBackwardsCompatibilityWithoutHuggingFaceUsername() throws {
        let yamlContent = """
        modelName: test-model
        textModelName: custom-text-model
        modelCacheDir: /test/cache
        maxTokens: 256
        temperature: 0.1
        pdfDPI: 150
        verbose: false
        output:
          dateFormat: yyyy-MM-dd
          filenamePattern: "{date}_Rechnung_{company}.pdf"
        """

        let configPath = tempDirectory.appendingPathComponent("no_hf_config.yaml").path
        try yamlContent.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = try Configuration.load(from: configPath)

        XCTAssertEqual(config.textModelName, "custom-text-model")
        XCTAssertNil(config.huggingFaceUsername)
    }

    func testYAMLRoundTripWithNewFields() throws {
        let config = Configuration(
            modelName: "vlm-model",
            textModelName: "text-model",
            modelCacheDir: "/test/cache",
            huggingFaceUsername: "testuser"
        )

        let savePath = tempDirectory.appendingPathComponent("new_fields.yaml").path
        try config.save(to: savePath)
        let loaded = try Configuration.load(from: savePath)

        XCTAssertEqual(loaded.modelName, "vlm-model")
        XCTAssertEqual(loaded.textModelName, "text-model")
        XCTAssertEqual(loaded.huggingFaceUsername, "testuser")
    }

    func testDescriptionIncludesTextModel() {
        let config = Configuration(textModelName: "my-text-model")
        XCTAssertTrue(config.description.contains("my-text-model"))
        XCTAssertTrue(config.description.contains("Text Model:"))
    }

    func testDescriptionIncludesHuggingFaceUsername() {
        let config = Configuration(huggingFaceUsername: "hf-user")
        XCTAssertTrue(config.description.contains("hf-user"))
        XCTAssertTrue(config.description.contains("HuggingFace User:"))
    }

    func testDescriptionOmitsHuggingFaceUsernameWhenNil() {
        let config = Configuration()
        XCTAssertFalse(config.description.contains("HuggingFace User:"))
    }
}
