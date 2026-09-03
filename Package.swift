// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DoubaoVoiceRestore",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "DoubaoVoiceRestore", targets: ["DoubaoVoiceRestore"])
    ],
    targets: [
        .target(name: "VoiceRestoreCore", path: "Sources/VoiceRestoreCore"),
        .executableTarget(
            name: "DoubaoVoiceRestore",
            dependencies: ["VoiceRestoreCore"],
            path: "Sources/DoubaoVoiceRestore"
        ),
        .testTarget(
            name: "VoiceRestoreCoreTests",
            dependencies: ["VoiceRestoreCore"],
            path: "Tests/VoiceRestoreCoreTests"
        ),
    ]
)
