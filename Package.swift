// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CityDeveloper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CityDeveloper",
            path: "Sources/CityDeveloper"
        )
    ]
)
