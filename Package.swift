// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "shinobi",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShinobiKit", targets: ["ShinobiKit"]),
        .library(name: "PivotKit", targets: ["PivotKit"]),
        .library(name: "IdentityKit", targets: ["IdentityKit"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
    ],
    targets: [
        .target(name: "ShinobiKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShinobiKitTests", dependencies: ["ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "PivotKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "PivotKitTests", dependencies: ["PivotKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "IdentityKit", dependencies: ["ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "IdentityKitTests", dependencies: ["IdentityKit", "ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CaptureKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
