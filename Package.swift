// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fable",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Command Line Tools don't bundle XCTest or swift-testing, so pull
        // swift-testing in as a source dependency pinned to the local toolchain.
        .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "swift-6.2-RELEASE"),
    ],
    targets: [
        .executableTarget(
            name: "Fable",
            path: "Sources/Fable",
            resources: [
                .copy("Resources/versions.json"),
                .process("Resources/en.lproj"),
                .process("Resources/es.lproj"),
                .process("Resources/pt.lproj"),
            ]
        ),
        .testTarget(
            name: "FableTests",
            dependencies: [
                "Fable",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/FableTests"
        ),
    ]
)
