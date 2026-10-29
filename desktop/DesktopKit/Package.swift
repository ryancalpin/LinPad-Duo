// swift-tools-version: 5.10
import Foundation
import PackageDescription

// iPhone Duo hinge and fold APIs (iOS 27.1 SDK), used only in Core/Duo/DuoHinge.swift. On by
// default; LINPAD_HINGE_API=0 in the environment builds without them, for an older SDK
// (release/duo-build-ipa.sh sets it when Xcode's iOS SDK is older than 27.1).
let hingeAPI = ProcessInfo.processInfo.environment["LINPAD_HINGE_API"] != "0"

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
                swiftSettings: hingeAPI ? [.define("LINPAD_HINGE_API")] : []),
        .testTarget(name: "DesktopKitTests", dependencies: ["DesktopKit"], exclude: ["Fixtures"]),
    ]
)
