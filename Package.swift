// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheReadingRoom",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.6.0")
    ],
    targets: [
        // Rendering and file-tree logic, with no UI — so it can be tested.
        .target(
            name: "TheReadingRoomCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            // Resources are copied into the .app bundle by build.sh, not by SPM,
            // so the app can find them with a plain Bundle.main lookup.
            exclude: ["Resources"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TheReadingRoom",
            dependencies: ["TheReadingRoomCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TheReadingRoomCoreTests",
            dependencies: ["TheReadingRoomCore"]
        ),
    ]
)
