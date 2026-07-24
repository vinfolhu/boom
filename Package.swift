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
                "Resources/pet-chroma.png",
                "Resources/pet-sprite-chroma.png",
                "Resources/pet-sprite.png"
            ],
            resources: [
                .process("Resources")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
