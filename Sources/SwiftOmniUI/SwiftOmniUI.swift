// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The one UI import an application makes: SwiftUI itself where the platform
// ships it, the SwiftOmniUI engine everywhere else - the same spellings, the
// platform's own engine underneath.
//
// The engine lives in SwiftOmniUICore; code inside the package imports that
// module, never this facade - on Apple platforms this file answers SwiftUI
// instead.

@_exported import Foundation
#if canImport(SwiftUI)
@_exported import SwiftUI
#else
// The engine, its host-facing SPI included: `@_spi(Host) import SwiftOmniUI`
// in application heads keeps resolving what it resolved before the split.
@_spi(Host) @_exported import SwiftOmniUICore
// The Foundation-bound half - `Text(AttributedString)`, `.onOpenURL` and
// friends - and the model layer's view bridge - `@Query`, `.modelContainer`,
// `\.modelContext` - ride with the engine on platforms without SwiftUI; on
// Apple platforms they are SwiftUI's own, and the model layer comes from
// SwiftData via `import JsonData`.
@_exported import SwiftOmniUIFoundation
@_exported import SwiftOmniUIJsonData
#endif
