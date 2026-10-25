// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BabyLogKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BabyLogKit", targets: ["BabyLogKit"]),
    ],
    targets: [
        .target(name: "BabyLogKit"),
        .testTarget(name: "BabyLogKitTests", dependencies: ["BabyLogKit"]),
    ],
    swiftLanguageModes: [.v5]
)
