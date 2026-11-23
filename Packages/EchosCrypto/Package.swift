// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "EchosCrypto",
    products: [
        .library(name: "EchosCrypto", targets: ["EchosCrypto"]),
    ],
    targets: [
        .target(name: "EchosCrypto"),
        .testTarget(name: "EchosCryptoTests", dependencies: ["EchosCrypto"]),
    ]
)
