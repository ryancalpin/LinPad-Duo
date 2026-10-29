// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DesktopKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "DesktopKit", targets: ["DesktopKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.12"),
    ],
    targets: [
        .target(name: "DesktopKit", dependencies: [.product(name: "Perception", package: "swift-perception")], resources: [.copy("Resources/Wallpapers"), .copy("Resources/ColorThemes"), .copy("Resources/Fonts"), .copy("Resources/Icons"), .copy("Resources/Store")],
                swiftSettings: [
                    // iPhone Duo hinge and fold APIs (iOS 27.1 SDK), used only in Core/Duo/DuoHinge.swift.
                    // Delete this line to build without them (DUO-SETUP.md, step 3).
                    .define("LINPAD_HINGE_API"),
                ]),
        .testTarget(name: "DesktopKitTests", dependencies: ["DesktopKit"], exclude: ["Fixtures"]),
    ]
)
