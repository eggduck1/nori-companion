// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NoriCompanion",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NoriCore", targets: ["NoriCore"]),
        .executable(name: "NoriCompanion", targets: ["NoriCompanion"]),
    ],
    targets: [
        .target(name: "NoriCore"),
        .executableTarget(name: "NoriCompanion", dependencies: ["NoriCore"]),
        .executableTarget(name: "NoriCoreChecks", dependencies: ["NoriCore"], path: "Tests/NoriCoreChecks"),
    ]
)
