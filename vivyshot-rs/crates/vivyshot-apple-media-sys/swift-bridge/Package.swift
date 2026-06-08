// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VivyShotAppleMediaBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "VivyShotAppleMediaBridge",
            type: .static,
            targets: ["VivyShotAppleMediaBridge"])
    ],
    targets: [
        .target(
            name: "VivyShotAppleMediaBridge",
            path: "Sources/VivyShotAppleMediaBridge")
    ]
)
