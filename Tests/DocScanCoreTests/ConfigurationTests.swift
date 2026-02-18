@testable import DocScanCore
import XCTest

final class ConfigurationTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testDefaultConfiguration() {
        let config = Configuration.defaultConfiguration

        XCTAssertEqual(config.modelName, "mlx-community/Qwen2-VL-2B-Instruct-4bit")
        XCTAssertEqual(config.maxTokens, 256)
        XCTAssertEqual(config.temperature, 0.1)
        XCTAssertEqual(config.pdfDPI, 150)
        XCTAssertFalse(config.verbose)
        XCTAssertEqual(config.dateFormat, "yyyy-MM-dd")
        XCTAssertEqual(config.filenamePattern, "{date}_Rechnung_{company}.pdf")
    }

    func testCustomConfiguration() {
        let config = Configuration(
            modelName: "custom-model",
            modelCacheDir: "/tmp/models",
            maxTokens: 512,
            temperature: 0.5,
            pdfDPI: 300,
            verbose: true,
            output: OutputSettings(
                dateFormat: "dd-MM-yyyy",
                filenamePattern: "{company}_{date}.pdf"
            )
        )

        XCTAssertEqual(config.modelName, "custom-model")
        XCTAssertEqual(config.modelCacheDir, "/tmp/models")
        XCTAssertEqual(config.maxTokens, 512)
        XCTAssertEqual(config.temperature, 0.5)
        XCTAssertEqual(config.pdfDPI, 300)
        XCTAssertTrue(config.verbose)
        XCTAssertEqual(config.dateFormat, "dd-MM-yyyy")
        XCTAssertEqual(config.filenamePattern, "{company}_{date}.pdf")
    }

    func testConfigurationDescription() {
        let config = Configuration.defaultConfiguration
        let description = config.description

        XCTAssertTrue(description.contains("Configuration:"))
        XCTAssertTrue(description.contains("Model:"))
        XCTAssertTrue(description.contains("Cache:"))
    }

    func testOutputSettingsDefaultInit() {
        let settings = OutputSettings()

        XCTAssertEqual(settings.dateFormat, "yyyy-MM-dd")
        XCTAssertEqual(settings.filenamePattern, "{date}_Rechnung_{company}.pdf")
    }

    func testOutputSettingsCustomInit() {
        let settings = OutputSettings(
            dateFormat: "dd/MM/yyyy",
            filenamePattern: "{company}_{date}.pdf"
        )

        XCTAssertEqual(settings.dateFormat, "dd/MM/yyyy")
        XCTAssertEqual(settings.filenamePattern, "{company}_{date}.pdf")
    }

    func testOutputSettingsEquatable() {
        let settings1 = OutputSettings()
        let settings2 = OutputSettings()
        let settings3 = OutputSettings(dateFormat: "different")

        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }

    func testDateFormatConvenienceSetter() {
        var config = Configuration.defaultConfiguration

        XCTAssertEqual(config.dateFormat, "yyyy-MM-dd")

        config.dateFormat = "dd-MM-yyyy"

        XCTAssertEqual(config.dateFormat, "dd-MM-yyyy")
        XCTAssertEqual(config.output.dateFormat, "dd-MM-yyyy")
    }

    func testFilenamePatternConvenienceSetter() {
        var config = Configuration.defaultConfiguration

        XCTAssertEqual(config.filenamePattern, "{date}_Rechnung_{company}.pdf")

        config.filenamePattern = "{company}_{date}.pdf"

        XCTAssertEqual(config.filenamePattern, "{company}_{date}.pdf")
        XCTAssertEqual(config.output.filenamePattern, "{company}_{date}.pdf")
    }

    // MARK: - Default Model Cache Directory Tests

    func testDefaultModelCacheDirectory() {
        let config = Configuration()
        let expectedPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/docscan/models")
            .path
        XCTAssertEqual(config.modelCacheDir, expectedPath)
    }

    func testCustomModelCacheDirectory() {
        let config = Configuration(modelCacheDir: "/custom/path/models")
        XCTAssertEqual(config.modelCacheDir, "/custom/path/models")
    }

    // MARK: - Load Configuration Tests

    func testLoadConfigurationFromYAML() throws {
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

        let configPath = tempDirectory.appendingPathComponent("config.yaml").path
        try yamlContent.write(toFile: configPath, atomically: true, encoding: .utf8)

        let config = try Configuration.load(from: configPath)

        XCTAssertEqual(config.modelName, "test-model")
        XCTAssertEqual(config.modelCacheDir, "/test/cache")
        XCTAssertEqual(config.maxTokens, 512)
        XCTAssertEqual(config.temperature, 0.5)
        XCTAssertEqual(config.pdfDPI, 300)
        XCTAssertTrue(config.verbose)
        XCTAssertEqual(config.dateFormat, "dd-MM-yyyy")
        XCTAssertEqual(config.filenamePattern, "{company}_{date}.pdf")
    }

    func testLoadConfigurationFileNotFound() {
        let nonExistentPath = "/non/existent/config.yaml"

        XCTAssertThrowsError(try Configuration.load(from: nonExistentPath)) { error in
            guard let docScanError = error as? DocScanError else {
                XCTFail("Expected DocScanError")
                return
            }
            if case let .fileNotFound(path) = docScanError {
                XCTAssertEqual(path, nonExistentPath)
            } else {
                XCTFail("Expected fileNotFound error")
            }
        }
    }

    func testLoadConfigurationInvalidYAML() throws {
        let invalidYaml = """
        invalid: yaml: content:
        - this is not
        valid yaml [
        """

        let configPath = tempDirectory.appendingPathComponent("invalid.yaml").path
        try invalidYaml.write(toFile: configPath, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try Configuration.load(from: configPath))
    }

    // MARK: - Save Configuration Tests

    func testSaveConfiguration() throws {
        let config = Configuration(
            modelName: "saved-model",
            modelCacheDir: "/saved/cache",
            maxTokens: 1024,
            temperature: 0.8,
            pdfDPI: 200,
            verbose: true,
            output: OutputSettings(
                dateFormat: "yyyy/MM/dd",
                filenamePattern: "Invoice_{date}_{company}.pdf"
            )
        )

        let savePath = tempDirectory.appendingPathComponent("saved_config.yaml").path
        try config.save(to: savePath)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: savePath))

        // Load it back and verify
        let loadedConfig = try Configuration.load(from: savePath)
        XCTAssertEqual(loadedConfig.modelName, "saved-model")
        XCTAssertEqual(loadedConfig.modelCacheDir, "/saved/cache")
        XCTAssertEqual(loadedConfig.maxTokens, 1024)
        XCTAssertEqual(loadedConfig.temperature, 0.8)
        XCTAssertEqual(loadedConfig.pdfDPI, 200)
        XCTAssertTrue(loadedConfig.verbose)
        XCTAssertEqual(loadedConfig.dateFormat, "yyyy/MM/dd")
        XCTAssertEqual(loadedConfig.filenamePattern, "Invoice_{date}_{company}.pdf")
    }

    func testSaveAndLoadRoundTrip() throws {
        let originalConfig = Configuration.defaultConfiguration
        let savePath = tempDirectory.appendingPathComponent("roundtrip.yaml").path

        try originalConfig.save(to: savePath)
        let loadedConfig = try Configuration.load(from: savePath)

        XCTAssertEqual(originalConfig.modelName, loadedConfig.modelName)
        XCTAssertEqual(originalConfig.maxTokens, loadedConfig.maxTokens)
        XCTAssertEqual(originalConfig.temperature, loadedConfig.temperature)
        XCTAssertEqual(originalConfig.pdfDPI, loadedConfig.pdfDPI)
        XCTAssertEqual(originalConfig.verbose, loadedConfig.verbose)
        XCTAssertEqual(originalConfig.dateFormat, loadedConfig.dateFormat)
        XCTAssertEqual(originalConfig.filenamePattern, loadedConfig.filenamePattern)
    }

    // MARK: - Description Tests

    func testDescriptionContainsAllFields() {
        let config = Configuration(
            modelName: "test-model",
            modelCacheDir: "/test/cache",
            maxTokens: 256,
            temperature: 0.1,
            pdfDPI: 150,
            verbose: false
        )

        let description = config.description

        XCTAssertTrue(description.contains("test-model"))
        XCTAssertTrue(description.contains("/test/cache"))
        XCTAssertTrue(description.contains("256"))
        XCTAssertTrue(description.contains("0.1"))
        XCTAssertTrue(description.contains("150"))
        XCTAssertTrue(description.contains("false"))
    }
}
