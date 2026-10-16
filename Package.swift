// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MDacViewer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MDacViewer"
        )
    ]
)
