// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "AetherAtlas",
  platforms: [.macOS("26.0")],
  products: [.library(name: "AetherCore", targets: ["AetherCore"])],
  targets: [
    .target(name: "AetherCore", resources: [.copy("Resources/GameDataIndex.json")]),
    .testTarget(
      name: "AetherCoreTests", dependencies: ["AetherCore"], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
