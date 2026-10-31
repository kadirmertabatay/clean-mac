// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CleanMac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "CleanMac", path: "Sources/CleanMac"),
        .testTarget(name: "CleanMacTests", dependencies: ["CleanMac"], path: "Tests/CleanMacTests"),
    ]
)
