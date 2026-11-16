// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KKvoice",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "KKvoice", targets: ["KKvoice"])],
    targets: [
        .target(name: "VoiceSessions", path: "Session"),
        .target(name: "RemoteAudio", path: "Audio"),
        .target(name: "SnapNote", path: "SnapNote", exclude: ["INTEGRATION.md"]),
        .executableTarget(name: "KKvoice", dependencies: ["VoiceSessions", "RemoteAudio", "SnapNote"], path: "Sources/KKvoice"),
        .testTarget(name: "KKvoiceTests", dependencies: ["KKvoice", "VoiceSessions", "RemoteAudio"], path: "Tests/KKvoiceTests")
    ]
)
