// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HUDson",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "HUDson", path: "Sources/HUDson")
    ],
    swiftLanguageModes: [.v5]
)
