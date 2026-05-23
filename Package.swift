// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CommitPyramid",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CommitPyramid",
            path: "Sources/CityDeveloper",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CommitPyramidTests",
            dependencies: ["CommitPyramid"],
            path: "Tests/CityDeveloperTests"
        )
    ]
)
