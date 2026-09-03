// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MornUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MornUsageBar",
            path: "Sources/MornUsageBar"
        ),
        .testTarget(
            name: "MornUsageBarTests",
            dependencies: ["MornUsageBar"],
            path: "Tests/MornUsageBarTests"
        ),
    ]
)
