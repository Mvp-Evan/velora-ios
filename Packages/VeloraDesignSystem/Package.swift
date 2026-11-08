// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VeloraDesignSystem",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "VeloraDesignSystem", targets: ["VeloraDesignSystem"]),
    ],
    targets: [
        .target(name: "VeloraDesignSystem", path: "Sources"),
    ]
)
