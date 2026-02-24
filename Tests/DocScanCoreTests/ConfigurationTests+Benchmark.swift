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
        XCTAssertEqual(config.modelName, "mlx-community/Qwen2-VL-7B-Instruct-4bit")
    }

    func testDefaultHuggingFaceUsernameIsNil() {
        let config = Configuration.defaultConfiguration
        XCTAssertNil(config.benchmark.huggingFaceUsername)
    }

    func testCustomHuggingFaceUsername() {
        let config = Configuration(benchmark: BenchmarkSettings(huggingFaceUsername: "my-hf-user"))
        XCTAssertEqual(config.benchmark.huggingFaceUsername, "my-hf-user")
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
        XCTAssertNil(config.benchmark.huggingFaceUsername)
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
        XCTAssertNil(config.benchmark.huggingFaceUsername)
    }

    func testYAMLRoundTripWithNewFields() throws {
        let config = Configuration(
            modelName: "vlm-model",
            textModelName: "text-model",
            modelCacheDir: "/test/cache",
            benchmark: BenchmarkSettings(huggingFaceUsername: "testuser")
        )

        let savePath = tempDirectory.appendingPathComponent("new_fields.yaml").path
        try config.save(to: savePath)
        let loaded = try Configuration.load(from: savePath)

        XCTAssertEqual(loaded.modelName, "vlm-model")
        XCTAssertEqual(loaded.textModelName, "text-model")
        XCTAssertEqual(loaded.benchmark.huggingFaceUsername, "testuser")
    }

    func testDescriptionIncludesTextModel() {
        let config = Configuration(textModelName: "my-text-model")
        XCTAssertTrue(config.description.contains("my-text-model"))
        XCTAssertTrue(config.description.contains("Text Model:"))
    }

    func testDescriptionIncludesHuggingFaceUsername() {
        let config = Configuration(benchmark: BenchmarkSettings(huggingFaceUsername: "hf-user"))
        XCTAssertTrue(config.description.contains("hf-user"))
        XCTAssertTrue(config.description.contains("HuggingFace User:"))
    }

    func testDescriptionOmitsHuggingFaceUsernameWhenNil() {
        let config = Configuration()
        XCTAssertFalse(config.description.contains("HuggingFace User:"))
    }

    // MARK: - BenchmarkSettings

    func testBenchmarkSettingsEquatable() {
        let settings1 = BenchmarkSettings(huggingFaceUsername: "user", vlmModels: ["m1"])
        let settings2 = BenchmarkSettings(huggingFaceUsername: "user", vlmModels: ["m1"])
        let settings3 = BenchmarkSettings(huggingFaceUsername: "other")

        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }

    // MARK: - Benchmark Property Setters

    func testHuggingFaceUsernameSetter() {
        var config = Configuration()
        XCTAssertNil(config.benchmark.huggingFaceUsername)

        config.benchmark.huggingFaceUsername = "new-user"

        XCTAssertEqual(config.benchmark.huggingFaceUsername, "new-user")
    }

    func testBenchmarkVLMModelsSetter() {
        var config = Configuration()
        XCTAssertNil(config.benchmark.vlmModels)

        config.benchmark.vlmModels = ["model/a", "model/b"]

        XCTAssertEqual(config.benchmark.vlmModels, ["model/a", "model/b"])
    }

    func testBenchmarkTextLLMModelsSetter() {
        var config = Configuration()
        XCTAssertNil(config.benchmark.textLLMModels)

        config.benchmark.textLLMModels = ["model/x"]

        XCTAssertEqual(config.benchmark.textLLMModels, ["model/x"])
    }

    // MARK: - Benchmark Model Lists

    func testDefaultBenchmarkModelListsAreNil() {
        let config = Configuration.defaultConfiguration
        XCTAssertNil(config.benchmark.vlmModels)
        XCTAssertNil(config.benchmark.textLLMModels)
    }

    func testCustomBenchmarkModelLists() {
        let vlmModels = ["model/vlm-a", "model/vlm-b"]
        let textModels = ["model/text-a", "model/text-b"]
        let config = Configuration(
            benchmark: BenchmarkSettings(vlmModels: vlmModels, textLLMModels: textModels)
        )
        XCTAssertEqual(config.benchmark.vlmModels, vlmModels)
        XCTAssertEqual(config.benchmark.textLLMModels, textModels)
    }

    func testYAMLBackwardsCompatibilityWithoutBenchmarkModels() throws {
        let yamlContent = """
        modelName: test-model
        textModelName: text-model
        modelCacheDir: /test/cache
        maxTokens: 256
        temperature: 0.1
        pdfDPI: 150
        verbose: false
        output:
          dateFormat: yyyy-MM-dd
          filenamePattern: "{date}_Rechnung_{company}.pdf"
        """

        let configPath = tempDirectory.appendingPathComponent("no_benchmark_models.yaml").path
        try yamlContent.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = try Configuration.load(from: configPath)
        XCTAssertNil(config.benchmark.vlmModels)
        XCTAssertNil(config.benchmark.textLLMModels)
    }

    func testYAMLRoundTripWithBenchmarkModels() throws {
        let config = Configuration(
            benchmark: BenchmarkSettings(vlmModels: ["vlm/a", "vlm/b"], textLLMModels: ["text/a"])
        )

        let savePath = tempDirectory.appendingPathComponent("benchmark_models.yaml").path
        try config.save(to: savePath)
        let loaded = try Configuration.load(from: savePath)

        XCTAssertEqual(loaded.benchmark.vlmModels, ["vlm/a", "vlm/b"])
        XCTAssertEqual(loaded.benchmark.textLLMModels, ["text/a"])
    }

    func testYAMLRoundTripWithAllBenchmarkFields() throws {
        let config = Configuration(
            benchmark: BenchmarkSettings(
                huggingFaceUsername: "user123",
                vlmModels: ["vlm/x"],
                textLLMModels: ["text/y", "text/z"]
            )
        )

        let path = tempDirectory.appendingPathComponent("all_benchmark.yaml").path
        try config.save(to: path)
        let loaded = try Configuration.load(from: path)

        XCTAssertEqual(loaded.benchmark.huggingFaceUsername, "user123")
        XCTAssertEqual(loaded.benchmark.vlmModels, ["vlm/x"])
        XCTAssertEqual(loaded.benchmark.textLLMModels, ["text/y", "text/z"])
    }
}
