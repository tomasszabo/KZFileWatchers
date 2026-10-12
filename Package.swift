// swift-tools-version:6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KZFileWatchers",
    platforms: [.macOS(.v12), .iOS(.v15), .tvOS(.v15)],
    products: [
        .library(name: "KZFileWatchers", targets: ["KZFileWatchers"]),
        .library(name: "KZFileWatchersObjC", targets: ["KZFileWatchersObjC"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(name: "KZFileWatchers", dependencies: []),
        .target(name: "KZFileWatchersObjC", dependencies: ["KZFileWatchers"], path: "ObjcWrappers"),
        .testTarget(name: "KZFileWatchersTests", dependencies: ["KZFileWatchers", "KZFileWatchersObjC"])
    ],
    swiftLanguageModes: [.v6]
)
