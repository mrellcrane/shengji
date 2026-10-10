// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ShengjiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShengjiCore", targets: ["ShengjiCore"]),
    ],
    targets: [
        .target(name: "ShengjiCore"),
        // Writes the JSON parity vectors for the TypeScript engine in server/:
        //   swift run ShengjiVectors ../server/test/vectors
        // Not part of the library product, so the iOS app is unaffected.
        .executableTarget(name: "ShengjiVectors", dependencies: ["ShengjiCore"]),
        .testTarget(name: "ShengjiCoreTests", dependencies: ["ShengjiCore"]),
    ]
)
