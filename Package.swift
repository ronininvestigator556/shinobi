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
        .library(name: "MonitorKit", targets: ["MonitorKit"]),
        .library(name: "BookmarkKit", targets: ["BookmarkKit"]),
        .library(name: "CaseKit", targets: ["CaseKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
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
        .target(name: "MonitorKit", dependencies: ["ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "MonitorKitTests", dependencies: ["MonitorKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "BookmarkKit", dependencies: ["ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "BookmarkKitTests", dependencies: ["BookmarkKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .target(name: "CaseKit", dependencies: ["ShinobiKit", .product(name: "GRDB", package: "GRDB.swift")], swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "CaseKitTests", dependencies: ["CaseKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
