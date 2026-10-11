import SwiftOmniUI

/// `Image(systemName:)` names a symbol in the PLATFORM's own set - a Segoe
/// Fluent glyph on Windows, an icon-theme name on Linux. There is no shared
/// table: the caller names its own platform.
struct SymbolSample: SampleContent, ExampleContent {
    static let id = "symbol"
    static let title = "Symbols"
    static let summary = "The platform's own symbol, asked for by its own name - "
        + "Fluent glyph or icon theme."

    /// (caption, systemName) pairs - the caption is what a reader of the row
    /// sees; the name is what `Image(systemName:)` is handed. Each platform
    /// speaks its own vocabulary, so each names every symbol its own way.
    #if os(Windows)
    private static let symbols: [(String, String)] = [
        ("E734", "\u{E734}"),
        ("EB51", "\u{EB51}"),
        ("E80F", "\u{E80F}"),
        ("E713", "\u{E713}"),
        ("E721", "\u{E721}"),
        ("E8A4", "\u{E8A4}"),
        ("E71B", "\u{E71B}"),
        ("E8DD", "\u{E8DD}"),
        ("E701", "\u{E701}"),
        ("E74D", "\u{E74D}"),
        ("E70F", "\u{E70F}"),
        ("E8B7", "\u{E8B7}"),
        ("E787", "\u{E787}"),
        ("E946", "\u{E946}"),
        ("E768", "\u{E768}"),
        ("E72E", "\u{E72E}"),
    ]
    #else
    private static let symbols: [(String, String)] = [
        ("star", "star-symbolic"),
        ("heart", "heart-symbolic"),
        ("home", "go-home-symbolic"),
        ("settings", "cogged-wheel-symbolic"),
        ("search", "loupe-symbolic"),
        ("bookmark", "bookmark-symbolic"),
        ("link", "chain-link-symbolic"),
        ("bold", "text-bold-symbolic"),
        ("wireless", "radiowaves-3-symbolic"),
        ("trash", "user-trash-symbolic"),
        ("pencil", "pencil-symbolic"),
        ("folder", "folder-symbolic"),
        ("calendar", "calendar-symbolic"),
        ("info", "info-outline-symbolic"),
        ("play", "media-playback-start-symbolic"),
        ("lock", "padlock-closed-symbolic"),
    ]
    #endif

    static let code = """
        // A symbol is named in the platform's own vocabulary. Pick it at the
        // call site with #if - the host's spelling, one Image:
        Image(systemName: {
            #if os(Windows)
            return "\\u{E701}"
            #else
            return "radiowaves-3-symbolic"
            #endif
        }())

        ForEach(0..<symbols.count) { at in
            let (caption, name) = symbols[at]
            VStack {
                Image(systemName: name)
                    .resizable()
                    .frame(width: 24)
                    .frame(height: 24)
                Text(caption)
                    .font(.system(size: 10, design: .monospaced))
            }
        }
        """

    var body: some View {
        VStack {
            ForEach(0..<4, id: \.self) { row in
                HStack {
                    ForEach(0..<4, id: \.self) { col in
                        let (caption, name) = Self.symbols[row * 4 + col]
                        VStack {
                            Image(systemName: name)
                                .resizable()
                                .frame(width: 24)
                                .frame(height: 24)

                            Text(caption)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Palette.subtle)
                        }
                        .spacing(6)
                        .frame(width: 96)
                    }
                }
                .spacing(8)
                .horizontalAlignment(.center)
            }
        }
        .spacing(16)
    }

    var notes: (any View)? {
        VStack {
            Text("`systemName` is the platform's own word for a symbol - there "
                + "is no shared list inside the library. On a Mac it is the SF "
                + "Symbols name; on Windows the Segoe Fluent glyph itself, "
                + "written as the character (`\"\\u{E701}\"`); on Linux the "
                + "name the icon theme answers, and the icons the library "
                + "ships are registered with that theme.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("A name no set knows draws the platform's missing-symbol "
                + "placeholder - the icon is declared where it is used, behind "
                + "`#if os(...)`, so adding one platform to a button is a "
                + "one-line change beside the other two.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
