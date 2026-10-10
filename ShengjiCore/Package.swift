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
        .testTarget(name: "ShengjiCoreTests", dependencies: ["ShengjiCore"]),
    ]
)
