// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClippyMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClippyMac",
            path: "Sources/ClippyMac",
            resources: [.process("Resources")]
        )
    ]
)
