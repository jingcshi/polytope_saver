// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Polychora",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PolychoraSaver", type: .dynamic, targets: ["PolychoraSaver"]),
        .executable(name: "PolychoraPreview", targets: ["PolychoraPreview"]),
        .executable(name: "PolychoraAppex", targets: ["PolychoraAppex"]),
        .executable(name: "PolychoraHost", targets: ["PolychoraHost"]),
    ],
    dependencies: [
        .package(url: "https://github.com/AerialScreensaver/PaperSaver.git",
                 revision: "f38915ef1a4ac9e6c7a840802562d52a9f24fb8b"),
    ],
    targets: [
        .target(name: "PolytopeKit"),
        .target(name: "PolychoraRender", dependencies: ["PolytopeKit"]),
        .target(name: "PolychoraSaver", dependencies: ["PolychoraRender"]),
        .target(name: "ScreenSaverPrivate", linkerSettings: [.linkedFramework("ScreenSaver")]),
        .executableTarget(name: "PolychoraAppex", dependencies: ["PolychoraRender", "ScreenSaverPrivate"]),
        .executableTarget(name: "PolychoraHost",
                          dependencies: [.product(name: "PaperSaverKit", package: "PaperSaver")]),
        .executableTarget(name: "PolychoraPreview", dependencies: ["PolychoraRender"]),
        .testTarget(name: "PolytopeKitTests", dependencies: ["PolytopeKit"]),
        .testTarget(name: "PolychoraRenderTests", dependencies: ["PolychoraRender"]),
    ],
    swiftLanguageModes: [.v5]
)
