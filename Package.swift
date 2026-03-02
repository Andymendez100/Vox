// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SttTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SttTool", targets: ["SttTool"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
    ],
    targets: [
        .executableTarget(
            name: "SttTool",
            dependencies: [
                "WhisperKit"
            ],
            path: "SttTool",
            exclude: ["SttTool.entitlements", "Info.plist"],
            resources: [
                .copy("Resources/AppIcon.icns")
            ]
        )
    ]
)
