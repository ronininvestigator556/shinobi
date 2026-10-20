// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-or-later
import PackageDescription

let package = Package(
    name: "shinobi",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "ShinobiKit", targets: ["ShinobiKit"]),
    ],
    targets: [
        .target(name: "ShinobiKit", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ShinobiKitTests", dependencies: ["ShinobiKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
