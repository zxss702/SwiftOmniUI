// swift-tools-version:6.4
import PackageDescription

// One package owns every SwiftOmniUI module. Internal dependencies are targets;
// ordinary library products expose those modules to applications.
let settings: [SwiftSetting] = [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
let host = ["Android", "WinUI", "GTK", "Web"]
    .first { $0.lowercased() == Context.environment["SWIFTOMNIUI_HOST"] }
let selectedHost = host
var products: [Product] = [
    .library(name: "SwiftOmniUI", targets: ["SwiftOmniUI"]),
    .library(name: "SwiftOmniUICore", targets: ["SwiftOmniUICore"]),
    .library(name: "SwiftOmniUIHost", targets: ["SwiftOmniUIHost"]),
    .library(name: "SwiftOmniUIFoundation", targets: ["SwiftOmniUIFoundation"]),
    .library(name: "SwiftOmniUIConformance", targets: ["SwiftOmniUIConformance"]),
    .library(name: "SwiftOmniUIHead", targets: ["SwiftOmniUIHead"]),
]

// The facade's own dependencies: engine-bound only where the platform ships
// no SwiftUI; on Apple platforms it depends on nothing at all.
var facadeDependencies: [Target.Dependency] = [
    .target(name: "SwiftOmniUICore", condition: .when(platforms: [.linux, .windows, .android, .wasi])),
    .target(name: "SwiftOmniUIFoundation", condition: .when(platforms: [.linux, .windows, .android, .wasi])),
]
#if !os(macOS)
facadeDependencies += [
    .target(name: "SwiftOmniUIJsonData", condition: .when(platforms: [.linux, .windows, .android, .wasi])),
]
#endif

var targets: [Target] = [
        // The facade an application imports: SwiftUI where the platform ships
        // it, the engine everywhere else - see Sources/SwiftOmniUI.
        .target(
            name: "SwiftOmniUI",
            dependencies: facadeDependencies,
            path: "Sources/SwiftOmniUI",
            swiftSettings: settings
        ),
        // The engine itself: imported by every target in this package, reached
        // by an application only through the facade above.
        .target(
            name: "SwiftOmniUICore",
            path: "lib/SwiftOmniUI/Sources",
            swiftSettings: settings
        ),
        .target(
            name: "SwiftOmniUIHost",
            dependencies: ["SwiftOmniUICore"],
            path: "lib/SwiftOmniUI.Host/Sources",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .target(
            name: "SwiftOmniUIFoundation",
            dependencies: ["SwiftOmniUICore"],
            path: "lib/SwiftOmniUI.Foundation/Sources",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .target(
            name: "SwiftOmniUIConformance",
            dependencies: ["SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.Conformance/Sources",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .target(
            name: "SwiftOmniUIHead",
            dependencies: host.map { [.target(name: "SwiftOmniUI\($0)")] } ?? [],
            path: "lib/SwiftOmniUI.Head/Sources",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
                + (host.map { [.define($0.uppercased())] } ?? []),
            // A WinUI head is a windowed application: started by itself it opens no console, and started from one it
            // writes there. A Web head's module exports its function table, through which the page calls the host
            // back, and its stack is the main thread's on macOS and Linux, 8 MB, below its data, so running out of
            // it stops the program rather than overwriting what lies beyond (docs/design/platforms/web/runtime.md).
            linkerSettings: host == "WinUI"
                ? [.unsafeFlags(["-Xlinker", "/SUBSYSTEM:WINDOWS", "-Xlinker", "/ENTRY:mainCRTStartup"])]
                : host == "Web"
                ? [.unsafeFlags(["-Xlinker", "--export-table", "-Xlinker", "--stack-first",
                    "-Xlinker", "-z", "-Xlinker", "stack-size=8388608", "-Xlinker", "--global-base=8388608"]),
                   // A release page carries no debugging information: 14.5 MB of HelloWorld rather than 23.7.
                   .unsafeFlags(["-Xlinker", "--strip-debug"], .when(configuration: .release))]
                : []
        ),
]

// Device and Web suites use their own platform runners.
if selectedHost != "Android" && selectedHost != "Web" {
    targets += [
        .testTarget(name: "SwiftOmniUITests", dependencies: ["SwiftOmniUICore"],
            path: "lib/SwiftOmniUI/Tests", swiftSettings: settings),
        .testTarget(
            name: "SwiftOmniUIHostTests",
            dependencies: ["SwiftOmniUIHost", "SwiftOmniUICore"],
            path: "lib/SwiftOmniUI.Host/Tests",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "SwiftOmniUIFoundationTests",
            dependencies: ["SwiftOmniUIFoundation"],
            path: "lib/SwiftOmniUI.Foundation/Tests",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "SwiftOmniUIConformanceTests",
            dependencies: ["SwiftOmniUIConformance", "SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.Conformance/Tests",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
    ]
}

switch selectedHost {
case "GTK"?:
    products += [
        .library(name: "SwiftOmniUIGTK", targets: ["SwiftOmniUIGTK"]),
        .library(name: "SwiftOmniUIWebViewGTK", targets: ["SwiftOmniUIWebViewGTK"]),
    ]
    targets += [
        .systemLibrary(name: "CSwiftOmniUIGTK", path: "lib/SwiftOmniUI.GTK/Sources/CSwiftOmniUIGTK", pkgConfig: "libadwaita-1"),
        .target(
            name: "SwiftOmniUIGTK",
            dependencies: ["CSwiftOmniUIGTK", "SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.GTK/Sources/SwiftOmniUIGTK",
            resources: [.copy("Resources/Icons")],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")],
            // The fonts an application registers are fontconfig's; the font map told they changed is pangoft2's.
            linkerSettings: [
                .linkedLibrary("fontconfig"), .linkedLibrary("pangoft2-1.0"), .linkedLibrary("pangocairo-1.0"),
            ]
        ),
        .testTarget(
            name: "SwiftOmniUIGTKTests",
            dependencies: [
                "SwiftOmniUIGTK", "CSwiftOmniUIGTK", "SwiftOmniUICore",
                "SwiftOmniUIHost",
                "SwiftOmniUIConformance",
                "SwiftOmniUIWebViewGTK",
            ],
            path: "lib/SwiftOmniUI.GTK/Tests",
            exclude: ["Resources"],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .systemLibrary(name: "CWebKitGTK", path: "lib/Backends/WebView.GTK/Sources/CWebKitGTK", pkgConfig: "webkitgtk-6.0"),
        .target(
            name: "SwiftOmniUIWebViewGTK",
            dependencies: [
                "CWebKitGTK",
                "SwiftOmniUIHost",
                "SwiftOmniUIGTK",
                "SwiftOmniUICore",
            ],
            path: "lib/Backends/WebView.GTK/Sources/SwiftOmniUIWebViewGTK", swiftSettings: settings + [.define("GTK")]),
    ]
case "WinUI"?:
    products += [
        .library(name: "SwiftOmniUIWinUI", targets: ["SwiftOmniUIWinUI"]),
        .library(name: "SwiftOmniUIWebViewWinUI", targets: ["SwiftOmniUIWebViewWinUI"]),
    ]
    targets += [
        .target(
            name: "CSwiftOmniUIWinUI",
            path: "lib/SwiftOmniUI.WinUI/Sources/CSwiftOmniUIWinUI",
            cxxSettings: [.headerSearchPath("../../.projection")],
            // An SVG is handed to WinUI from memory; a zone's offset is ICU's, and the kept values stand in the
            // user's local data; a canvas draws with Direct2D and DirectWrite on a Direct3D device.
            linkerSettings: [
                .linkedLibrary("shcore"), .linkedLibrary("shlwapi"), .linkedLibrary("icu"), .linkedLibrary("shell32"),
                .linkedLibrary("ole32"), .linkedLibrary("d2d1"), .linkedLibrary("d3d11"), .linkedLibrary("dwrite"),
                .linkedLibrary("windowscodecs"), .linkedLibrary("gdi32"),
            ]
        ),
        .target(
            name: "SwiftOmniUIWinUI",
            dependencies: ["CSwiftOmniUIWinUI", "SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.WinUI/Sources/SwiftOmniUIWinUI",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .testTarget(
            name: "SwiftOmniUIWinUITests",
            dependencies: [
                "SwiftOmniUIWinUI", "CSwiftOmniUIWinUI", "SwiftOmniUICore",
                "SwiftOmniUIWebViewWinUI",
                "SwiftOmniUIHost",
                "SwiftOmniUIConformance",
            ],
            path: "lib/SwiftOmniUI.WinUI/Tests",
            // The pictures a test shows, read from where they stand rather than bundled.
            exclude: ["Resources"],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .target(
            name: "CWebViewWinUI",
            path: "lib/Backends/WebView.WinUI/Relay",
            cxxSettings: [.unsafeFlags(["-I", Context.packageDirectory + "/lib/SwiftOmniUI.WinUI/.projection"])],
            linkerSettings: [.linkedLibrary("shcore"), .linkedLibrary("shlwapi")]
        ),
        .target(
            name: "SwiftOmniUIWebViewWinUI",
            dependencies: [
                "CWebViewWinUI",
                "SwiftOmniUIHost",
                "SwiftOmniUIWinUI",
                "SwiftOmniUICore",
            ],
            path: "lib/Backends/WebView.WinUI/Sources/SwiftOmniUIWebViewWinUI", swiftSettings: settings + [.define("WINUI")]),
    ]
case "Android"?:
    products += [
        .library(name: "SwiftOmniUIAndroid", targets: ["SwiftOmniUIAndroid"]),
        // The APK loads this final test runner through JNI.
        .library(name: "SwiftOmniUIAndroidTests", type: .dynamic, targets: ["SwiftOmniUIAndroidTests"]),
    ]
    targets += [
        .target(
            name: "CSwiftOmniUIAndroid",
            path: "lib/SwiftOmniUI.Android/Sources/CSwiftOmniUIAndroid",
            linkerSettings: [.linkedLibrary("android"), .linkedLibrary("log")]
        ),
        .target(
            name: "SwiftOmniUIAndroid",
            dependencies: ["CSwiftOmniUIAndroid", "SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.Android/Sources/SwiftOmniUIAndroid",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .target(
            name: "SwiftOmniUIAndroidTests",
            dependencies: [
                "SwiftOmniUICore",
                "SwiftOmniUIAndroid",
                "SwiftOmniUIHost",
                "SwiftOmniUIConformance",
            ],
            path: "lib/SwiftOmniUI.Android/Tests/Sources",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
    ]
case "Web"?:
    products += [
        .library(name: "SwiftOmniUIWeb", targets: ["SwiftOmniUIWeb"]),
    ]
    targets += [
        .systemLibrary(name: "CSwiftOmniUIWeb", path: "lib/SwiftOmniUI.Web/Sources/CSwiftOmniUIWeb"),
        .target(
            name: "SwiftOmniUIWeb",
            dependencies: ["CSwiftOmniUIWeb", "SwiftOmniUICore",
                "SwiftOmniUIHost"],
            path: "lib/SwiftOmniUI.Web/Sources/SwiftOmniUIWeb",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
        .systemLibrary(name: "CWebTesting", path: "lib/SwiftOmniUI.Web/Testing/Sources/CWebTesting"),
        .testTarget(
            name: "SwiftOmniUIWebTests",
            dependencies: [
                "CWebTesting", "SwiftOmniUIWeb",
                "SwiftOmniUIHost", "SwiftOmniUICore",
                "SwiftOmniUIConformance",
            ],
            path: "lib/SwiftOmniUI.Web/Testing/Tests",
            exclude: ["Resources"],
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")],
            // The stack a Web head links with: 8 MB, first in memory (docs/design/platforms/web/runtime.md#the-stack).
            linkerSettings: [.unsafeFlags([
                "-Xlinker", "--export-table", "-Xlinker", "--stack-first",
                "-Xlinker", "-z", "-Xlinker", "stack-size=8388608", "-Xlinker", "--global-base=8388608",
            ])]
        ),
    ]
default:
    break
}

// The model-layer bridge: `JsonDataCore` only exists where SwiftData does
// not, so the module has no meaning on an Apple host.
#if !os(macOS)
products += [.library(name: "SwiftOmniUIJsonData", targets: ["SwiftOmniUIJsonData"])]
targets += [
    .target(
        name: "SwiftOmniUIJsonData",
        dependencies: [
            "SwiftOmniUICore",
            // The same ordinary JsonData product applications consume.
            .product(name: "JsonData", package: "JsonData"),
        ],
        path: "lib/SwiftOmniUI.JsonData/Sources",
        swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
    ),
]
if selectedHost != "Android" && selectedHost != "Web" {
    targets += [
        .testTarget(
            name: "SwiftOmniUIJsonDataTests",
            dependencies: ["SwiftOmniUIJsonData"],
            path: "lib/SwiftOmniUI.JsonData/Tests",
            swiftSettings: [.enableUpcomingFeature("NonisolatedNonsendingByDefault")]
        ),
    ]
}
#endif

// An application outside this repository depends on the published package:
//
//     .package(url: "https://github.com/zxss702/SwiftOmniUI.git", exact: "0.5.2")
let package = Package(
    name: "SwiftOmniUIRoot",
    platforms: [.iOS(.v26), .macCatalyst(.v26), .macOS(.v15)],
    products: products,
    dependencies: [.package(url: "https://github.com/zxss702/JsonData.git", branch: "main")],
    targets: targets,
    cxxLanguageStandard: .cxx20
)
