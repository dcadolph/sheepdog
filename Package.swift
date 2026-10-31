// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sheepdog",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SheepdogCore"),
        .executableTarget(
            name: "Sheepdog",
            dependencies: ["SheepdogCore"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "SheepdogCoreTests",
            dependencies: ["SheepdogCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "SheepdogTests",
            dependencies: ["Sheepdog", "SheepdogCore"]
        ),
    ]
)
