// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "NeroNookArk", platforms: [.macOS(.v14)], products: [.executable(name: "ArkPlugin", targets: ["ArkPlugin"])], dependencies: [.package(path: "Vendor/NookPluginSDK")], targets: [
    .target(name: "ArkCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .executableTarget(name: "ArkPlugin", dependencies: ["ArkCore", .product(name: "NookPluginSDK", package: "NookPluginSDK")], swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "ArkCoreTests", dependencies: ["ArkCore", "ArkPlugin"], swiftSettings: [.swiftLanguageMode(.v5)])])
