// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "mousetalk",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "double-click-key-test", targets: ["DoubleClickKeyTest"]),
        .executable(name: "DoubleClickMouse", targets: ["DoubleClickMouseApp"]),
        .executable(name: "mousetalk-check", targets: ["MouseTalkCheck"]),
    ],
    targets: [
        .executableTarget(name: "DoubleClickKeyTest"),
        .target(name: "MouseTalkKit"),
        .executableTarget(name: "DoubleClickMouseApp", dependencies: ["MouseTalkKit"]),
        .executableTarget(name: "MouseTalkCheck", dependencies: ["MouseTalkKit"]),
        .testTarget(name: "MouseTalkKitTests", dependencies: ["MouseTalkKit"]),
    ],
    swiftLanguageModes: [.v5]
)
