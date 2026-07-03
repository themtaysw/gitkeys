// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GitKeys",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "GitKeys",
            path: "Sources/GitKeys"
        )
    ]
)
