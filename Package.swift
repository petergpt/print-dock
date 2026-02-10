// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PrintDock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "PrintDockKit", targets: ["PrintDockKit"]),
        .executable(name: "PrintDock", targets: ["PrintDockApp"]),
        .executable(name: "printdock", targets: ["PrintDockCLI"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PrintDockKit",
            path: "Sources/PrintDockKit"
        ),
        .executableTarget(
            name: "PrintDockApp",
            dependencies: ["PrintDockKit"],
            path: "Sources/PrintDockApp",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "PrintDockCLI",
            dependencies: ["PrintDockKit"],
            path: "Sources/PrintDockCLI",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PrintDockCLI/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PrintDockKitTests",
            dependencies: ["PrintDockKit"],
            path: "Tests/PrintDockKitTests"
        ),
        .testTarget(
            name: "PrintDockAppTests",
            dependencies: ["PrintDockApp", "PrintDockKit"],
            path: "Tests/PrintDockAppTests"
        )
    ]
)
