// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "double-click-mouse",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "double-click-key-test", targets: ["DoubleClickKeyTest"]),
        .executable(name: "DoubleClickMouse", targets: ["DoubleClickMouseApp"]),
    ],
    targets: [
        .executableTarget(name: "DoubleClickKeyTest"),
        .executableTarget(name: "DoubleClickMouseApp"),
    ],
    swiftLanguageModes: [.v5]
)
