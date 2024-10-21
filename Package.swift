// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NetworkChangeNotifier",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
    ],
    products: [
        .library(
            name: "NetworkChangeNotifier",
            targets: ["NetworkChangeNotifier"]),
    ],
    dependencies: [
        .package(url: "https://github.com/codingiran/SwiftyTimer.git", .upToNextMajor(from: "2.0.2")),
    ],
    targets: [
        .target(
            name: "NetworkChangeNotifier",
            dependencies: [
                "SwiftyTimer",
            ],
            path: "Sources",
            resources: [.copy("Resources/PrivacyInfo.xcprivacy")]),
        .testTarget(name: "NetworkChangeNotifierTests", dependencies: ["NetworkChangeNotifier"]),
    ])
