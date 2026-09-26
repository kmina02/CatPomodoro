// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CatPomodoro",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "CatPomodoro", targets: ["CatPomodoro"])
    ],
    targets: [
        .executableTarget(
            name: "CatPomodoro",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
