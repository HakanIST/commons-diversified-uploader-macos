// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "UploaderCore",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "UploaderCore", targets: ["UploaderCore"]),
        .executable(name: "cdu-cli", targets: ["cdu-cli"]),
    ],
    targets: [
        .binaryTarget(name: "onnxruntime", path: "../../Frameworks/onnxruntime.xcframework"),
        .target(name: "UploaderCore", dependencies: ["onnxruntime"]),
        .executableTarget(name: "cdu-cli", dependencies: ["UploaderCore"]),
        .testTarget(name: "UploaderCoreTests", dependencies: ["UploaderCore"]),
    ]
)
