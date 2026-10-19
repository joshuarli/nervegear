// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nervegear",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nervegear", targets: ["Nervegear"]),
    ],
    targets: [
        .executableTarget(
            name: "Nervegear",
            path: "Sources/Nervegear",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ModelIO"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("GameController"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
