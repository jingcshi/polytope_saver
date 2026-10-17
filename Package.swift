// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Polychora",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PolychoraSaver", type: .dynamic, targets: ["PolychoraSaver"]),
        .executable(name: "PolychoraPreview", targets: ["PolychoraPreview"]),
    ],
    targets: [
        .target(name: "PolytopeKit"),
        .target(name: "PolychoraRender", dependencies: ["PolytopeKit"]),
        .target(name: "PolychoraSaver", dependencies: ["PolychoraRender"]),
        .executableTarget(name: "PolychoraPreview", dependencies: ["PolychoraRender"]),
        .testTarget(name: "PolytopeKitTests", dependencies: ["PolytopeKit"]),
    ],
    swiftLanguageModes: [.v5]
)
