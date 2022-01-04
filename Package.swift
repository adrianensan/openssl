// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "OpenSSL",
    platforms: [.iOS(.v12), .macOS(.v10_15)],
    products: [
        .library(
            name: "OpenSSL",
            targets: ["OpenSSL"]),
    ],
    dependencies: [],
    targets: [
      .binaryTarget(name: "OpenSSL", path: "OpenSSL.xcframework")
    ]
)
