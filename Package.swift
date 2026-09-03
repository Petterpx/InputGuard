// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "InputGuard",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "InputGuard", targets: ["InputGuard"])
    ],
    targets: [
        .target(name: "InputGuardCore", path: "Sources/InputGuardCore"),
        .executableTarget(
            name: "InputGuard",
            dependencies: ["InputGuardCore"],
            path: "Sources/InputGuard"
        ),
        .testTarget(
            name: "InputGuardCoreTests",
            dependencies: ["InputGuardCore"],
            path: "Tests/InputGuardCoreTests"
        ),
    ]
)
