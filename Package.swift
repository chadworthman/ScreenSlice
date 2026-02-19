// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreenSlice",
    platforms: [.macOS(.v15)],
    targets: [
        .target(
            name: "CGVirtualDisplayPrivate",
            path: "ScreenSlice/CGVirtualDisplayPrivate",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "ScreenSlice",
            dependencies: ["CGVirtualDisplayPrivate"],
            path: "ScreenSlice/Sources",
            exclude: ["Info.plist"]
        ),
    ]
)
