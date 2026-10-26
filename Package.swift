// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "AIO",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(name: "AIO", path: "Sources/AIO", swiftSettings: [.swiftLanguageMode(.v5)])
    ]
)
