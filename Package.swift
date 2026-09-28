// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Audio6",
    platforms: [.macOS(.v13)],
    targets: [
        // Small C layer for USB control transfers (IOKit macros are easiest from C)
        .target(
            name: "TA6USB",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]
        ),
        .executableTarget(name: "Audio6", dependencies: ["TA6USB"]),
    ]
)
