// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The clipboard, asked as an act like every question for the platform.

/// The clipboard: text the user carries between applications.
///
///     try await Pasteboard.copy(commit.hex)
///
public enum Pasteboard {
    /// Publishes a native image, retaining its encoded contents for later paste requests.
    public static nonisolated(nonsending) func copy(_ image: BitmapImage) async throws {
        try await stateUICall(AppContract.copyImage, ImageSource(bitmap: image))
    }
    /// Publishes HTML and the Markdown/plain text alternative in one clipboard item.
    public static nonisolated(nonsending) func copy(html: String, plainText: String) async throws {
        try await stateUICall(AppContract.copyRichText, html, plainText)
    }

    /// Puts `text` on the clipboard, replacing what it held.
    ///
    /// - Throws: `SwiftOmniUIError` when there is no page on screen to ask
    ///   through.
    public static nonisolated(nonsending) func copy(_ text: String) async throws {
        try await stateUICall(AppContract.copyText, text)
    }
}
