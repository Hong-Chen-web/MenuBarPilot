// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuBarPilot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "MenuBarPilot",
            targets: ["MenuBarPilot"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MenuBarPilot",
            path: "MenuBarPilot",
            exclude: [
                "Info.plist",
                "MenuBarPilot.entitlements"
            ],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
