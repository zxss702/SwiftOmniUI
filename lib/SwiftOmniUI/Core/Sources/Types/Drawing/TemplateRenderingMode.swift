// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// How a picture takes colour - what `.renderingMode` takes on an `Image`:
///
///     Image("logo.png")
///         .renderingMode(.original)
public enum TemplateRenderingMode: Int32, Sendable {
    /// Drawn as written - its own colours.
    case original = 0

    /// Drawn as a stencil - its shape in the surrounding foreground colour.
    case template = 1
}

extension TemplateRenderingMode: HostRepresentable {}
extension TemplateRenderingMode: StateChoice {}
