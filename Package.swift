// swift-tools-version: 5.10
import PackageDescription

// KeyboardLockCore holds the pure, UI-free logic for KeyboardLock so it can be
// exercised with `swift test` in CI (SPEC §9.5 / TEST-C) and unit-tested with
// mocked collaborators (SPEC ARCH-5). The Xcode `KeyboardLock.app` target links
// this same package; AppKit / SwiftUI / IOKit-glue stays in the app target.
let package = Package(
    name: "KeyboardLockCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "KeyboardLockCore", targets: ["KeyboardLockCore"]),
    ],
    targets: [
        .target(name: "KeyboardLockCore"),
        .testTarget(
            name: "KeyboardLockCoreTests",
            dependencies: ["KeyboardLockCore"]
        ),
    ]
)
