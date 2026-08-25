// swift-tools-version: 5.9
import PackageDescription

// Bang-for-Buck — local Core package (the app's spine).
//
// This package MUST NOT import SwiftUI / UIKit / Vision. That boundary is what
// forces the pure/impure split (conventions §7) and keeps the whole value engine
// unit-testable without a camera or a simulator (Architecture §3).
//
// Dependency direction points DOWN only (§4):
//     CoreModel        <- nothing
//     CoreContracts    <- CoreModel
//     CoreServices     <- CoreModel, CoreContracts
//
// No `platforms:` restriction on purpose: the pure core is platform-agnostic and
// builds on Linux, so `swift test` runs anywhere. The Apple frameworks live in the
// app's Infrastructure layer, behind the CoreContracts protocols.

let package = Package(
    name: "Core",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "CoreModel", targets: ["CoreModel"]),
        .library(name: "CoreContracts", targets: ["CoreContracts"]),
        .library(name: "CoreServices", targets: ["CoreServices"]),
    ],
    targets: [
        .target(name: "CoreModel"),
        .target(name: "CoreContracts", dependencies: ["CoreModel"]),
        .target(name: "CoreServices", dependencies: ["CoreModel", "CoreContracts"]),

        .testTarget(name: "CoreModelTests", dependencies: ["CoreModel"]),
        .testTarget(name: "CoreContractsTests", dependencies: ["CoreContracts", "CoreModel"]),
        .testTarget(
            name: "CoreServicesTests",
            dependencies: ["CoreServices", "CoreContracts", "CoreModel"]
        ),
    ]
)
