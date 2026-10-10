// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumaTouch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LumaTouch", targets: ["LumaTouch"])],
    targets: [
        .executableTarget(name: "LumaTouch")
    ],
    swiftLanguageModes: [.v5]
)
