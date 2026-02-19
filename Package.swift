// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSlice",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenSlice",
            path: "ScreenSlice",
            exclude: ["Info.plist"]
        ),
    ]
)
