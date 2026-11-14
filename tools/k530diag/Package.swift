// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "k530diag",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(name: "k530diag", path: "Sources/k530diag")
    ]
)
