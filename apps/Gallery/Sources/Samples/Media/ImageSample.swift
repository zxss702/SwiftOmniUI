import SwiftOmniUI

/// Pictures from the app's resources: fitted, filled, and one per color scheme.
struct ImageSample: SampleContent, ExampleContent {
    static let id = "image"
    static let title = "Image"
    static let summary = "A picture from the app's resources, asked for by name."

    static let code = """
        VStack {
            HStack {
                Image(light: "nav_home.png", dark: "nav_home_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_layout.png", dark: "nav_layout_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_input.png", dark: "nav_input_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_shell.png", dark: "nav_shell_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)
            }

            // The same square picture in the same wide box, so the only thing
            // between the two is the aspect: fit keeps the whole picture and
            // leaves room, fill covers the box and crops.
            HStack {
                VStack {
                    Image(light: "nav_media.png", dark: "nav_media_dark.png")
                        .scaledToFit()
                        .frame(width: 120)
                        .frame(height: 60)

                    Text(".scaledToFit()")
                }

                VStack {
                    Image(light: "nav_media.png", dark: "nav_media_dark.png")
                        .scaledToFill()
                        .frame(width: 120)
                        .frame(height: 60)

                    Text(".scaledToFill()")
                }
            }

            // A systemName names a symbol in the platform's own set - the SF
            // name on a Mac, the Fluent glyph on Windows, the theme name on
            // Linux. The call site picks with #if.
            HStack {
                Image(systemName: {
                    #if os(Windows)
                    return "\\u{E734}"
                    #else
                    return "star-symbolic"
                    #endif
                }())
                    .resizable()
                    .frame(width: 24)
                    .frame(height: 24)

                Label("Starred", systemImage: {
                    #if os(Windows)
                    return "\\u{E734}"
                    #else
                    return "star-symbolic"
                    #endif
                }())
            }

            // `.clipShape` cuts the view to the outline a shape stands for.
            HStack {
                Image("nav_media.png")
                    .scaledToFill()
                    .frame(width: 48)
                    .frame(height: 48)
                    .clipShape(Circle())

                Text("clipped to a circle")
            }

            // The same shape drawn black, and drawn once per color scheme. An Image
            // has no tint, so what changes is the SOURCE.
            HStack {
                Image("nav_gestures.png")
                    .frame(width: 32)
                    .frame(height: 32)

                Text("black artwork, always")
            }

            HStack {
                Image(light: "nav_gestures.png", dark: "nav_gestures_dark.png")
                    .frame(width: 32)
                    .frame(height: 32)

                Text("one per colorScheme - switch the system between light and dark")
            }
        }
        """

    var body: some View {
        VStack {
            HStack {
                Image(light: "nav_home.png", dark: "nav_home_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_layout.png", dark: "nav_layout_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_input.png", dark: "nav_input_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)

                Image(light: "nav_shell.png", dark: "nav_shell_dark.png")
                    .frame(width: 48)
                    .frame(height: 48)
            }
            .spacing(16)

            SectionTitle("Fit or fill")

            // The same square picture in the same wide box, so the only thing
            // between the two is the aspect.
            HStack {
                VStack {
                    Image(light: "nav_media.png", dark: "nav_media_dark.png")
                        .scaledToFit()
                        .frame(width: 120)
                        .frame(height: 60)
                        .background(Palette.surface)

                    Text(".scaledToFit()")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)
                }
                .spacing(4)

                VStack {
                    Image(light: "nav_media.png", dark: "nav_media_dark.png")
                        .scaledToFill()
                        .frame(width: 120)
                        .frame(height: 60)
                        .background(Palette.surface)

                    Text(".scaledToFill()")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.subtle)
                        .multilineTextAlignment(.center)
                }
                .spacing(4)
            }
            .spacing(16)

            SectionTitle("One per colorScheme")

            // The same shape drawn black and white. An Image has no tint, so
            // what changes is the SOURCE - and the half in force is picked as
            // the view is built, so switching the system color scheme builds this
            // view again with the other file.
            HStack {
                Image("nav_gestures.png")
                    .frame(width: 32)
                    .frame(height: 32)

                Text("black artwork, always")
                    .font(.system(size: 13))
            }
            .spacing(12)

            HStack {
                Image(light: "nav_gestures.png", dark: "nav_gestures_dark.png")
                    .frame(width: 32)
                    .frame(height: 32)

                Text("one per colorScheme - switch the system between light and dark")
                    .font(.system(size: 13))
            }
            .spacing(12)

            SectionTitle("Symbols")

            // `systemName` names a symbol, not a file: the host draws the one
            // its own set knows - SF Symbols on a Mac, Fluent Icons on
            // Windows, the icon theme on Linux. Each platform names them its
            // own way, so the list itself is per-platform.
            HStack {
                #if os(Windows)
                let names = ["\u{E735}", "\u{EB51}", "\u{E80F}", "\u{E713}", "\u{E721}"]
                #else
                let names = ["star-symbolic", "heart-symbolic", "go-home-symbolic", "cogged-wheel-symbolic", "loupe-symbolic"]
                #endif

                ForEach(names, id: \.self) { name in
                    Image(systemName: name)
                        .resizable()
                        .frame(width: 24)
                        .frame(height: 24)
                }
            }
            .spacing(16)

            // A Label is a title with a symbol at its head - and its style
            // picks which of the two shows.
            HStack {
                Label("Starred", systemImage: {
                    #if os(Windows)
                    return "\u{E734}"
                    #else
                    return "star-symbolic"
                    #endif
                }())

                Label("Bookmarked", systemImage: {
                    #if os(Windows)
                    return "\u{E8A4}"
                    #else
                    return "bookmark-symbolic"
                    #endif
                }())
                    .labelStyle(.iconOnly)
                    .frame(width: 24)
                    .frame(height: 24)
            }
            .spacing(16)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("The first row is the sidebar's own icons: SVGs in `Resources/Images`, "
                + "each asked for by its `.png` name. Where the build makes no PNG of that "
                + "name, the host loads the SVG of the same name instead.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`.aspect` is the choice between showing all of the picture and filling "
                + "every corner: `.fit` keeps the whole picture and leaves room on "
                + "two sides, `.fill` covers the box and crops what will not fit.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("An `Image` has no tint, so a picture that has to read on both themes is "
                + "two pictures. `ImageSource(light:dark:)` is picked the way "
                + "`Color(light:dark:)` is - as the view is built - so a change of colorScheme "
                + "builds the views wearing one again.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`Image(systemName:)` asks for no file: the name is a symbol "
                + "in the PLATFORM's own set - the Segoe Fluent glyph itself on "
                + "Windows, the icon-theme name on Linux. The library holds no "
                + "table between them; the call site names its own platform "
                + "behind `#if os(...)`. `Label` pairs one with a title, and "
                + "`.labelStyle` picks which shows.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`.isAnimating(true)` runs a picture that HAS frames - a GIF, an "
                + "animated WebP - and does nothing at all to a still one, which is why "
                + "no example above uses it: the gallery ships no animated artwork. It is "
                + "a property rather than an act, so a paused animation is a state the "
                + "tree describes and a rebuild cannot lose.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}
