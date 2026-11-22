// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickyMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "StickyMac", path: "Sources/StickyMac")
    ]
)
