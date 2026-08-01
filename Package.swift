// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Batteries",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Batteries",
            path: "Sources/Batteries"
        ),
        .testTarget(
            name: "BatteriesTests",
            dependencies: ["Batteries"],
            path: "Tests/BatteriesTests"
        )
    ]
)
