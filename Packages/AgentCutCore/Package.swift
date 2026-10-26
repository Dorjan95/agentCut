// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentCutCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentCutCore", targets: ["AgentCutCore"]),
    ],
    targets: [
        .target(name: "AgentCutCore"),
        .testTarget(name: "AgentCutCoreTests", dependencies: ["AgentCutCore"]),
    ]
)
