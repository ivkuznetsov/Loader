// swift-tools-version: 5.6
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Loader",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v15)
    ],
    products: [
        .library(name: "Loader", targets: ["Loader"]),
        .library(name: "LoaderUI", targets: ["LoaderUI"])
    ],
    dependencies: [],
    targets: [
        .target(name: "Loader", dependencies: []),
        .target(name: "LoaderUI", dependencies: ["Loader"])
    ]
)
