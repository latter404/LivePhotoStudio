// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "LivePhotoStudio", platforms: [.macOS(.v14)], products: [.executable(name: "LivePhotoStudio", targets: ["LivePhotoStudio"])], targets: [.executableTarget(name: "LivePhotoStudio"), .testTarget(name: "LivePhotoStudioTests", dependencies: ["LivePhotoStudio"])])
