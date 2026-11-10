// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DramaPlayer",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ReelsPlaybackCore", targets: ["ReelsPlaybackCore"]),
        .library(name: "ReelsPlaybackUIKit", targets: ["ReelsPlaybackUIKit"])
    ],
    targets: [
        .target(name: "ReelsPlaybackCore"),
        .target(name: "ReelsPlaybackUIKit", dependencies: ["ReelsPlaybackCore"]),
        .testTarget(name: "ReelsPlaybackCoreTests", dependencies: ["ReelsPlaybackCore"])
    ]
)
