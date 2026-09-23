// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MicMute",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MicMuteCore"),
        .testTarget(name: "MicMuteCoreTests", dependencies: ["MicMuteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
