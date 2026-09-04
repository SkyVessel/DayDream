// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DayDream",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DayDream",
            path: "Sources/DayDream"
        ),
        .testTarget(
            name: "DayDreamTests",
            dependencies: ["DayDream"],
            path: "Tests/DayDreamTests"
        )
    ]
)
