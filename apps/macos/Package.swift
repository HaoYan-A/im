// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IM",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "IM", targets: ["IM"]),
    ],
    dependencies: [
        // Reads Codex's config.toml.
        .package(url: "https://github.com/LebJe/TOMLKit", exact: "0.6.0"),
    ],
    targets: [
        // Platform logic with no UI: GitHub API, Keychain, git, repository layout, MCP configs.
        .target(name: "IMCore", dependencies: ["TOMLKit"]),
        // The menu bar app.
        .executableTarget(name: "IM", dependencies: ["IMCore"]),
        .testTarget(name: "IMCoreTests", dependencies: ["IMCore"]),
    ]
)
