import XCTest
@testable import DocScanCore

final class ConfigurationTests: XCTestCase {
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
}
