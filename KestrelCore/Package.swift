// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KestrelCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "KestrelCore", targets: ["KestrelCore"])],
    targets: [
        .target(name: "KestrelCore"),
        .testTarget(name: "KestrelCoreTests", dependencies: ["KestrelCore"]),
    ]
)
