// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DocScan",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "docscan",
            targets: ["DocScanCLI"]
        ),
        .library(
            name: "DocScanCore",
            targets: ["DocScanCore"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        // Core library with all invoice processing logic
        .target(
            name: "DocScanCore",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXLinalg", package: "mlx-swift"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "Transformers", package: "swift-transformers"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
            ],
            path: "Sources/DocScanCore"
        ),

        // CLI executable
        .executableTarget(
            name: "DocScanCLI",
            dependencies: [
                "DocScanCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/DocScanCLI"
        ),

        // Tests
        .testTarget(
            name: "DocScanCoreTests",
            dependencies: ["DocScanCore"],
            path: "Tests/DocScanCoreTests"
        ),
    ]
)
