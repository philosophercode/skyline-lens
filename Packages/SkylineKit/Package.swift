// swift-tools-version: 5.9
import PackageDescription

// SkylineKit holds everything except the thin app shell.
//
// - SkylineCore:    pure Swift geometry (geodesy, rotations, camera projection,
//                   compass ticks). No Apple frameworks, so it builds and tests
//                   on Linux CI as well as macOS.
// - SkylineSensors: Core Motion attitude + Core Location / barometer.
// - SkylineCamera:  AVFoundation capture session and preview layer.
// - SkylineUI:      SwiftUI live view, compass overlay, debug HUD.
//
// The Apple-only targets wrap their sources in `#if os(iOS)` so `swift test`
// works on macOS and Linux without a simulator.
let package = Package(
    name: "SkylineKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(
            name: "SkylineKit",
            targets: ["SkylineCore", "SkylineSensors", "SkylineCamera", "SkylineUI"]
        ),
    ],
    targets: [
        .target(name: "SkylineCore"),
        .target(name: "SkylineSensors", dependencies: ["SkylineCore"]),
        .target(name: "SkylineCamera", dependencies: ["SkylineCore"]),
        .target(name: "SkylineUI", dependencies: ["SkylineCore", "SkylineSensors", "SkylineCamera"]),
        .testTarget(name: "SkylineCoreTests", dependencies: ["SkylineCore"]),
    ]
)
