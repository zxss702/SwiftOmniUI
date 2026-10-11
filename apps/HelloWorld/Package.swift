// swift-tools-version:6.4
import PackageDescription

// The application's own Swift module, HelloWorldUI, and its head for the host a
// build is for. SourceKit understands only code a SwiftPM package holds, so the
// editor completes the application through this manifest as well.

// The host a build is for: SWIFTOMNIUI_HOST - android, winui, gtk or web -
// which its script or the editor sets, or none for plain Swift. The
// application's Swift for that host alone stands under its condition -
// `#if GTK` - and the root package brings the host itself to the head.
let host = ["Android", "WinUI", "GTK", "Web"]
    .first { $0.lowercased() == Context.environment["SWIFTOMNIUI_HOST"] }

// NonisolatedNonsendingByDefault is the one setting an application must not
// leave out; see the note in ../../Package.swift.
let settings: [SwiftSetting] = [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
    + (host.map { [.define($0.uppercased())] } ?? [])

var products: [Product] = [
    // The application module; a platform head depends on its target.
    .library(name: "HelloWorldUI", type: host == "Web" ? nil : .dynamic, targets: ["HelloWorldUI"]),
]

var targets: [Target] = [
    .target(name: "HelloWorldUI",
        dependencies: [.product(name: "SwiftOmniUI", package: "SwiftOmniUIRoot")], path: "Sources", swiftSettings: settings),
    // The application's tests - `swift test`, or SwiftOmniUI: Run Tests.
    .testTarget(name: "HelloWorldTests", dependencies: ["HelloWorldUI"], path: "Tests", swiftSettings: settings),
]

// The head in Platforms/<Host>: an executable its host runs, and on Android a
// library the platform loads. SwiftOmniUIHead brings the host.
let head: [Target.Dependency] = ["HelloWorldUI", .product(name: "SwiftOmniUIHead", package: "SwiftOmniUIRoot")]
switch host {
case "Android"?:
    products.append(.library(name: "HelloWorldAndroid", type: .dynamic, targets: ["HelloWorldAndroid"]))
    targets.append(.target(
        name: "HelloWorldAndroid", dependencies: head, path: "Platforms/Android/Swift", swiftSettings: settings))
case "WinUI"?:
    targets.append(.executableTarget(
        name: "HelloWorldWinUI",
        dependencies: head + [.product(name: "SwiftOmniUIWinUI", package: "SwiftOmniUIRoot")],
        path: "Platforms/WinUI", swiftSettings: settings))
case "GTK"?:
    targets.append(.executableTarget(
        name: "HelloWorldGTK",
        dependencies: head + [.product(name: "SwiftOmniUIGTK", package: "SwiftOmniUIRoot")],
        path: "Platforms/GTK", swiftSettings: settings))
case let host?:
    targets.append(.executableTarget(
        name: "HelloWorld\(host)", dependencies: head, path: "Platforms/\(host)", swiftSettings: settings))
case nil:
    break
}

let package = Package(
    name: "HelloWorldUI",
    // SwiftOmniUI's floor, which an application cannot go below.
    platforms: [
        .iOS(.v26),
        .macCatalyst(.v26),
        .macOS(.v15),
    ],
    products: products,
    // The SwiftOmniUI checkout: the library at its root, and a head's host.
    // Named, so the checkout's folder may carry any name - a path dependency's
    // identity would otherwise be the folder's.
    // An application outside this repository names the published package
    // instead, and changes nothing else:
    //
    //     .package(url: "https://github.com/zxss702/SwiftOmniUI.git", exact: "0.5.2")
    dependencies: [.package(name: "SwiftOmniUIRoot", path: "../..")],
    targets: targets
)
