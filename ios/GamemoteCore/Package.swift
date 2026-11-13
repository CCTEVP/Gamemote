// swift-tools-version: 6.0
// GamemoteCore: everything that is not UI. Protocol v0, device link, mock device, console log.
// Builds and tests with `swift test` (macOS) and is used by the Gamemote app in ios/.
import PackageDescription

let package = Package(
    name: "GamemoteCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "GamemoteCore", targets: ["GamemoteCore"]),
    ],
    targets: [
        .target(name: "GamemoteCore"),
        .testTarget(name: "GamemoteCoreTests", dependencies: ["GamemoteCore"]),
    ],
    swiftLanguageModes: [.v5]
)
