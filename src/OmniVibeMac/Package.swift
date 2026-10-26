// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OmniVibeMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OmniVibeMac", targets: ["OmniVibeMac"]),
        .executable(name: "OmniVibeFixture", targets: ["OmniVibeFixture"]),
        .library(name: "OmniVibeCore", targets: ["OmniVibeCore"])
    ],
    targets: [
        .target(name: "OmniVibeCore"),
        .executableTarget(name: "OmniVibeMac", dependencies: ["OmniVibeCore"],
                          resources: [.copy("Resources/Localization")]),
        .executableTarget(name: "OmniVibeFixture"),
        .testTarget(name: "OmniVibeCoreTests", dependencies: ["OmniVibeCore"]),
        .testTarget(name: "OmniVibeMacTests", dependencies: ["OmniVibeMac", "OmniVibeCore"])
    ]
)
