// swift-tools-version:6.4
import PackageDescription

// The application's own Swift module, GalleryUI, its acceptance tests, and its
// head for the host a build is for. SourceKit understands only code a SwiftPM
// package holds, so the editor completes the application through this
// manifest as well.

// The host a build is for: SWIFTOMNIUI_HOST - android, winui, gtk or web -
// which its script or the editor sets, or none for plain Swift - and then
// `swift test` compiles no line of any host's half. The application's Swift for that host alone stands under its
// condition - `#if GTK` - and the root package brings the host itself
// to the head.
let host = ["Android", "WinUI", "GTK", "Web"]
    .first { $0.lowercased() == Context.environment["SWIFTOMNIUI_HOST"] }

// NonisolatedNonsendingByDefault is the one setting an application must not
// leave out; see the note in ../../Package.swift.
let settings: [SwiftSetting] = [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
    + (host.map { [.define($0.uppercased())] } ?? [])

var products: [Product] = [
    // The application module; a platform head depends on its target.
    .library(name: "GalleryUI", type: host == "Web" ? nil : .dynamic, targets: ["GalleryUI"]),
]

var targets: [Target] = [
    .target(
        name: "GalleryUI",
        dependencies: [
            // The package is named by the dependency, never assumed from the
            // checkout's folder - a clone may sit in a directory of another
            // name (SwiftOmniUI, SwiftOmniUI-main).
            .product(name: "SwiftOmniUI", package: "SwiftOmniUIRoot"),
            .product(name: "SwiftOmniUIFoundation", package: "SwiftOmniUIRoot"),
            .product(name: "SwiftOmniUIJsonData", package: "SwiftOmniUIRoot"),
            .product(name: "JsonData", package: "JsonData"),
        ],
        // path: "Sources" - that whole folder is the app's code: the
        // application and its pages sit directly in it, Styles/ holds the
        // styles, and a directory added beside them is compiled without
        // being named here. Naming the folder rather than "." is what lets
        // the manifest sit beside the source and Resources/ without pulling
        // either host or artwork into the application module.
        path: "Sources",
        swiftSettings: settings),
    .testTarget(
        name: "GalleryTests",
        dependencies: [
            "GalleryUI",
            .product(name: "SwiftOmniUI", package: "SwiftOmniUIRoot"),
        ],
        path: "Tests/GalleryTests",
        swiftSettings: settings
    ),
]

// The head in Platforms/<Host>: an executable its host runs, and on Android a
// library the platform loads. SwiftOmniUIHead brings the host.
let head: [Target.Dependency] = ["GalleryUI", .product(name: "SwiftOmniUIHead", package: "SwiftOmniUIRoot")]
// The web view's backend where the host's platform does not ship one - GTK's WebKitGTK, WinUI's WebView2 - which
// the head registers: ../../lib/Backends/WebView.<Host>.
let webBackend: [Target.Dependency] = host.flatMap { host in
    ["GTK", "WinUI"].contains(host) ? [.product(name: "SwiftOmniUIWebView\(host)", package: "SwiftOmniUIRoot")] : nil
} ?? []
switch host {
case "Android"?:
    products.append(.library(name: "GalleryAndroid", type: .dynamic, targets: ["GalleryAndroid"]))
    targets.append(.target(
        name: "GalleryAndroid", dependencies: head + webBackend,
        path: "Platforms/Android/Swift", swiftSettings: settings))
case "WinUI"?:
    targets.append(.executableTarget(
        name: "GalleryWinUI",
        dependencies: head + webBackend + [.product(name: "SwiftOmniUIWinUI", package: "SwiftOmniUIRoot")],
        path: "Platforms/WinUI", swiftSettings: settings))
case "GTK"?:
    targets.append(.executableTarget(
        name: "GalleryGTK",
        dependencies: head + webBackend + [.product(name: "SwiftOmniUIGTK", package: "SwiftOmniUIRoot")],
        path: "Platforms/GTK", swiftSettings: settings))
case let host?:
    targets.append(.executableTarget(
        name: "Gallery\(host)", dependencies: head + webBackend, path: "Platforms/\(host)",
        swiftSettings: settings))
case nil:
    break
}

let package = Package(
    name: "GalleryUI",
    // SwiftOmniUI's floor, which an application cannot go below.
    platforms: [
        .iOS(.v26),
        .macCatalyst(.v26),
        .macOS(.v26),
    ],
    products: products,
    // The SwiftOmniUI checkout: the library at its root, and a head's host.
    // Named, so the checkout's folder may carry any name - a path dependency's
    // identity would otherwise be the folder's.
    dependencies: [
        // An application outside this repository names the published package
        // instead, and changes nothing else:
        //
        //     .package(url: "https://github.com/zxss702/SwiftOmniUI.git", exact: "0.5.2")
        .package(name: "SwiftOmniUIRoot", path: "../.."),
        .package(url: "https://github.com/zxss702/JsonData.git", branch: "main"),
    ],
    targets: targets
)
