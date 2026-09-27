// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Resticker",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "RestickerCore"),
        .executableTarget(name: "Resticker", dependencies: ["RestickerCore"]),
        .testTarget(name: "RestickerCoreTests", dependencies: ["RestickerCore"]),
    ]
)
