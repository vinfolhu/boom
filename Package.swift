// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BoomPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BoomPet", targets: ["BoomPet"])
    ],
    targets: [
        .executableTarget(
            name: "BoomPet",
            exclude: [
                "Resources/pet-chroma.png"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
