// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VeloraTestSupport",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "VeloraTestSupport", targets: ["VeloraTestSupport"]),
    ],
    targets: [
        .target(name: "VeloraTestSupport", path: "Sources"),
    ]
)
