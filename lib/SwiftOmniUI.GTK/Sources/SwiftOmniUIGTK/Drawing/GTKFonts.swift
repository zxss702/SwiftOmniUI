// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import CSwiftOmniUIGTK

/// The application's fonts: the files it carries, added to fontconfig's
/// application fonts - the list a Pango attribute's family resolves against.
/// Design: docs/design/platforms/gtk/drawing.md#the-applications-fonts
@MainActor
enum GTKFonts {
    /// The file at `path`, registered with fontconfig: the families inside
    /// answer `Font.custom`'s names, a font map made before being told the
    /// configuration changed. False where the platform could not read it.
    static func register(_ path: String) -> Bool {
        path.withCString { swiftomniui_gtk_font_added($0) } != 0
    }
}
