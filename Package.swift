// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MornAIMeter",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MornAIMeter",
            path: "Sources/MornAIMeter"
        ),
        .testTarget(
            name: "MornAIMeterTests",
            dependencies: ["MornAIMeter"],
            path: "Tests/MornAIMeterTests"
        ),
    ]
)
