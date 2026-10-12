// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The application's own fonts: the files it carries, handed to the platform's
// font registry so `Font.custom` can name the families inside.

/// The application's fonts: files it carries, added to the platform's font
/// registry so `Font.custom` can name the families inside - what
/// `CTFontManagerRegisterFontsForURL` is on Apple's platforms.
///
///     Fonts.register(path: Bundle.module.path(forResource: "Songti", ofType: "ttf")!)
///
/// Files are handed to the host's own registry as it starts, before it makes
/// a font context, so a `register` in `App.init` works wherever the app is
/// hosted; called after it has started, the platform answers as it does.
public enum Fonts {
    /// Adds the font file at `path` to the fonts `Font.custom` can name, for
    /// this process. A file is taken once: registering it again answers true
    /// and does nothing more.
    ///
    /// - Parameter path: the font file's path on disk.
    /// - Returns: whether the file was taken - by the host where it has
    ///   started, else held for it.
    @discardableResult
    public static func register(path: String) -> Bool {
        guard handled.insert(path).inserted else { return true }
        guard let add else {
            pending.append(path)
            return true
        }
        return add(path)
    }

    /// The paths `register` took before the host started, in order. A host
    /// hands each to `add` as it starts - before it makes a font context -
    /// then clears it.
    @_spi(Host) public nonisolated(unsafe) static var pending: [String] = []

    /// Every path `register` has taken, so a file is added to the platform's
    /// fonts once however often it is named.
    @_spi(Host) public nonisolated(unsafe) static var handled: Set<String> = []

    /// The add a host binds: a font file's path to whether the platform's font
    /// registry took it; nil where the host keeps no registry. Bound once as
    /// the host starts; called on the UI thread.
    @_spi(Host) public nonisolated(unsafe) static var add: ((String) -> Bool)?
}
