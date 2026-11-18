// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Omnicast",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Omnicast", targets: ["Omnicast"])
    ],
    dependencies: [
        .package(url: "https://github.com/Jakubantalik/Libraries.dev", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "Omnicast",
            dependencies: [
                .product(name: "VoiceGlowKit", package: "Libraries.dev")
            ],
            path: "Sources/Omnicast",
            // Compiled into Contents/Resources/default.metallib by
            // scripts/build.sh; SwiftPM does not build Metal sources itself.
            exclude: ["UI/SiriWave.metal"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "OmnicastTests",
            dependencies: ["Omnicast"],
            path: "Tests/OmnicastTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
