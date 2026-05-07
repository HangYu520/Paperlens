// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaperLens",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PaperLens", targets: ["PaperLens"])
    ],
    targets: [
        .executableTarget(
            name: "PaperLens",
            path: "Sources",
            resources: [
                .copy("Info.plist")
            ]
        )
    ]
)
