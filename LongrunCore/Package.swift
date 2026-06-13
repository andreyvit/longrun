// swift-tools-version: 6.2
// (6.2 is required for the `.macOS(.v26)` platform literal — do not lower it to
// match the app target's SWIFT_VERSION 6.0; those are independent axes.)
import PackageDescription

let package = Package(
    name: "LongrunCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "LongrunCore", targets: ["LongrunCore"]),
    ],
    targets: [
        // Headless process-supervision core. Default actor isolation is
        // SwiftPM's default (nonisolated) — keep it that way: this package must
        // never depend on SwiftUI/AppKit-UI.
        .target(name: "LongrunCore"),
        .testTarget(name: "LongrunCoreTests", dependencies: ["LongrunCore"]),
    ]
)
