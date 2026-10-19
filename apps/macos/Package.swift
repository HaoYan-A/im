// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IM",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "IM", targets: ["IM"]),
    ],
    targets: [
        // Platform logic with no UI: GitHub API, Keychain, git, repository layout.
        .target(name: "IMCore"),
        // The menu bar app.
        .executableTarget(name: "IM", dependencies: ["IMCore"]),
        .testTarget(name: "IMCoreTests", dependencies: ["IMCore"]),
    ]
)
