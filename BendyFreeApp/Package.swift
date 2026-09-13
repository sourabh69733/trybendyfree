// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BendyFree",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BendyFree", targets: ["BendyFree"])
    ],
    targets: [
        .executableTarget(
            name: "BendyFree",
            path: "Sources/BendyFree"
        ),
        .testTarget(name: "BendyFreeTests", dependencies: ["BendyFree"])
    ]
)
