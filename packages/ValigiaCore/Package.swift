// swift-tools-version: 5.9
// Logic package for the Valigia app. Pure Swift (Foundation only):
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "ValigiaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ValigiaCore", targets: ["ValigiaCore"])
    ],
    targets: [
        .target(
            name: "ValigiaCore",
            path: "Sources/ValigiaCore"
        ),
        .testTarget(
            name: "ValigiaCoreTests",
            dependencies: ["ValigiaCore"],
            path: "Tests/ValigiaCoreTests"
        )
    ]
)
