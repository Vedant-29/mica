// swift-tools-version: 6.2
import PackageDescription

// Everything in this app is main-actor work; opting in wholesale keeps AppKit
// interop free of per-declaration annotation noise.
let mainActorByDefault: [SwiftSetting] = [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Mica",
    platforms: [.macOS("15.0")],
    products: [
        .executable(name: "Mica", targets: ["Mica"])
    ],
    dependencies: [
        // Carbon RegisterEventHotKey under the hood — no Accessibility prompt,
        // and ships the SwiftUI recorder UI for the Shortcut settings tab.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "1.9.4"),
        // Reaches the underlying NSStatusItem from SwiftUI's MenuBarExtra.
        .package(url: "https://github.com/orchetect/MenuBarExtraAccess", from: "1.3.1"),
    ],
    targets: [
        // The engagement state machine and every system-mutating effect live here,
        // deliberately free of SwiftUI so the decision logic can be tested directly.
        // That logic is the part most likely to harbour subtle precedence and
        // idempotence bugs, and it is exactly the part a UI test cannot reach.
        .target(
            name: "MicaCore",
            path: "Sources/MicaCore",
            swiftSettings: mainActorByDefault
        ),
        .executableTarget(
            name: "Mica",
            dependencies: [
                "MicaCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MenuBarExtraAccess", package: "MenuBarExtraAccess"),
            ],
            path: "Sources/Mica",
            swiftSettings: mainActorByDefault
        ),
        .testTarget(
            name: "MicaCoreTests",
            dependencies: ["MicaCore"],
            path: "Tests/MicaCoreTests",
            swiftSettings: mainActorByDefault
        ),
    ]
)
