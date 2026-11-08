// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VeloraCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VeloraCore", targets: ["VeloraCore"]),
    ],
    targets: [
        .target(name: "VeloraCore", path: "Sources"),
        .testTarget(name: "VeloraCoreTests", dependencies: ["VeloraCore"], path: "Tests"),
    ]
)
