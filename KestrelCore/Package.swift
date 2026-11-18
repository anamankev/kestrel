// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KestrelCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "KestrelCore", targets: ["KestrelCore"])],
    targets: [
        // Argon2 reference implementation (CC0/Apache-2.0), vendored unmodified; see Sources/CArgon2/README.md.
        .target(name: "CArgon2", exclude: ["LICENSE", "README.md"],
                cSettings: [.define("ARGON2_NO_THREADS"), .headerSearchPath(".")]),
        .target(name: "KestrelCore", dependencies: ["CArgon2"]),
        .testTarget(name: "KestrelCoreTests", dependencies: ["KestrelCore"]),
    ]
)
