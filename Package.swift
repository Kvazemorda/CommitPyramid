// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CityDeveloper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CityDeveloper",
            path: "Sources/CityDeveloper",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "CityDeveloperTests",
            dependencies: ["CityDeveloper"],
            path: "Tests/CityDeveloperTests"
        )
    ]
)
