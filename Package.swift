// swift-tools-version:5.1
import PackageDescription

let package = Package(
    name: "KineticSensors",
    platforms: [.macOS(.v10_13), .iOS(.v9), .tvOS(.v10)],
    products: [
        .library(name: "KineticSensors", targets: ["KineticSensors"]),
    ],
    targets: [
        .target(name: "KineticSensors"),
    ]
)
