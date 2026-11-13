// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SimMonitor",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SimMonitorCore"),
        .executableTarget(name: "SimMonitor", dependencies: ["SimMonitorCore"]),
        .testTarget(name: "SimMonitorCoreTests", dependencies: ["SimMonitorCore"]),
    ]
)
