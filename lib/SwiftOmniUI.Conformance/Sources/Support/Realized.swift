// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// The case a lazy element's `realizedChanged` owes: the host tells which items it realized, at least once.
@_spi(Host) @MainActor public enum Realized {
    /// `element`'s realized set arrives, a list of the items the host mounted for it.
    public static func heard<Owner: Contract>(on element: String, _ event: ElementEvent<Owner, [String]>) -> ConformanceCase {
        ConformanceCase("\(element).tellsWhichItemsItRealized", proves: [
            Covered(event, on: element),
        ]) { s in
            let heard = Received<[String]>()
            s.start { Specimens.page(element, [Hear(event) { heard.values.append($0) }]) }
            try s.settle { !heard.values.isEmpty }
            s.expect(heard.values.isEmpty, false, "a realized set heard")
        }
    }
}
