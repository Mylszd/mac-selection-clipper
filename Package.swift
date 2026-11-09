// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MacSelectionClipper", platforms: [.macOS(.v13)], products: [
    .executable(name: "MacSelectionClipper", targets: ["MacSelectionClipper"])
], targets: [
    .target(name: "ClipperCore"),
    .target(name: "ClipperClipboard"),
    .executableTarget(name: "MacSelectionClipper", dependencies: ["ClipperCore", "ClipperClipboard"]),
    .executableTarget(name: "CoreChecks", dependencies: ["ClipperCore", "ClipperClipboard"], path: "Tests/CoreChecks")
])
