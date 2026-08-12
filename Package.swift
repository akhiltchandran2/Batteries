// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Batteries",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Only BatteriesQStore depends on this — the plain Batteries target
        // never imports Sparkle, so the personal build's binary has no link
        // dependency on it and needs no embedded framework at runtime.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "BatteriesCore",
            path: "Sources/BatteriesCore"
        ),
        .executableTarget(
            name: "Batteries",
            dependencies: ["BatteriesCore"],
            path: "Sources/Batteries"
        ),
        .executableTarget(
            name: "BatteriesQStore",
            dependencies: [
                "BatteriesCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/BatteriesQStore",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "BatteriesTests",
            dependencies: ["BatteriesCore"],
            path: "Tests/BatteriesTests"
        )
    ]
)
