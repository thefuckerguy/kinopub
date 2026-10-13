// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "WooFInstaller",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WooFInstaller", targets: ["WooFInstaller"])
    ],
    targets: [
        .executableTarget(
            name: "WooFInstaller",
            path: "Sources/WooFInstaller"
        ),
        .testTarget(
            name: "WooFInstallerTests",
            dependencies: ["WooFInstaller"],
            path: "Tests/WooFInstallerTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
