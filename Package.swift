// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NearGuard", platforms: [.macOS(.v14)], products: [.library(name: "NearGuardCore", targets: ["NearGuardCore"]), .executable(name: "NearGuard", targets: ["NearGuard"])], targets: [.target(name: "NearGuardCore"), .executableTarget(name: "NearGuard", dependencies: ["NearGuardCore"]), .testTarget(name: "NearGuardCoreTests", dependencies: ["NearGuardCore", "NearGuard"])], swiftLanguageModes: [.v5])
