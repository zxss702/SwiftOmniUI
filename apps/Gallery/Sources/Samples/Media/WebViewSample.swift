import SwiftOmniUI

/// A page of the web: fetched by URL, and HTML written in place.
struct WebViewSample: SampleContent {
    static let id = "webView"
    static let title = "WebView"
    static let summary = "A page of the web in the tree - fetched by URL, or HTML written in place."

    /// Held still: the web content scrolls ITSELF, and a page scroller above it
    /// would claim every drag - the rule every gesture sample follows.
    static let scrolls = false

    /// Each example is given the WINDOW's height: the web content scrolls
    /// itself, so a stated height would show the same sliver on every size of
    /// screen.
    static let fills = true

    var examples: [Example] {
        [Example(WebBrowserPart()), Example(WrittenInPlacePart())]
    }
}

/// The browser: a URL source, the platform's history reported into bindings,
/// and the four acts aimed at the view with `@Aim`.
private struct WebBrowserPart: ExampleContent {
    @State private var hasBack = false
    @State private var hasForward = false
    @State private var status = "nothing has loaded yet"
    @State private var answer = ""

    @Aim(WebView.self) private var browser

    static let code = """
        struct WebBrowserPart: View {
            @State private var hasBack = false
            @State private var hasForward = false
            @State private var status = "nothing has loaded yet"
            @State private var answer = ""

            @Aim(WebView.self) private var browser

            var body: some View {
                VStack {
                    HStack {
                        // The history flags are read by this bar, so every
                        // page that loads builds this closure.
                        Button("Back", action: { try await browser.goBack() })
                            .disabled(!hasBack)
                            

                        Button("Forward", action: { try await browser.goForward() })
                            .disabled(!hasForward)
                            

                        Button("Reload", action: { try await browser.reload() })
                            
                    }

                    // The browser takes all the height the window leaves -
                    // everything around it keeps its own height.
                    WebView("https://example.com")
                        .aim(browser)
                        // What the view calls itself to the server. Left
                        // unwritten it is the platform's own browser string.
                        .userAgent("SwiftOmniUI Gallery")
                        .canGoBack($hasBack)
                        .canGoForward($hasForward)
                        .onNavigating { report in
                            status = "fetching \\(report.url)"
                        }
                        .onNavigated { report in
                            status = "\\(report.result): \\(report.url)"
                        }
                        // The platform killed the web content process and left
                        // the view blank. Nothing else reports it.
                        .onProcessTerminated {
                            status = "the web process died - press Reload"
                        }
                        .frame(maxHeight: .infinity)

                    Text(status)

                    Button("Title?", action: {
                            answer = try await browser.evaluateJavaScript("document.title")
                        })
                        

                    Text(answer)
                }
            }
        }
        """

    var body: some View {
        VStack {

            HStack {
                Button("Back", action: { try await browser.goBack() })
                    .disabled(!hasBack)
                    .padding(EdgeInsets(14, 8))
                    

                Button("Forward", action: { try await browser.goForward() })
                    .disabled(!hasForward)
                    .padding(EdgeInsets(14, 8))
                    

                Button("Reload", action: { try await browser.reload() })
                    .padding(EdgeInsets(14, 8))
                    
            }
            .spacing(8)

            // The browser takes all the height the window leaves - everything
            // around it keeps its own height.
            WebView("https://example.com")
                .aim(browser)
                // What the view calls itself to the server. Left unwritten it
                // is the platform's own browser string.
                .userAgent("SwiftOmniUI Gallery")
                .canGoBack($hasBack)
                .canGoForward($hasForward)
                .onNavigating { report in
                    status = "fetching \(report.url)"
                }
                .onNavigated { report in
                    status = "\(report.result): \(report.url)"
                }
                // The platform killed the web content process and left the
                // view blank. Nothing else reports it.
                .onProcessTerminated {
                    status = "the web process died - press Reload"
                }
                .frame(maxHeight: .infinity)

            Text(status)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.accent)

            Button("Title?", action: {
                    answer = try await browser.evaluateJavaScript("document.title")
                })
                .padding(EdgeInsets(14, 8))
                

            Text(answer)
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(12)
    }

    var notes: (any View)? {
        VStack {
            Text("Follow the page's own link, and Back lights up: `canGoBack` and "
                + "`canGoForward` are reported into bindings after every navigation. "
                + "Back, Forward, Reload and the title question are acts aimed at the "
                + "view with `@Aim`.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)

            Text("`.onProcessTerminated` reports what no button here can provoke: the "
                + "platform runs web content in a process of its own and ends it when "
                + "memory runs short, which leaves the view blank. `reload()` brings the "
                + "page back.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.subtle)
        }
        .spacing(8)
    }
}

/// HTML written in the tree rather than fetched. Nothing here touches the
/// network.
private struct WrittenInPlacePart: ExampleContent {
    static let code = """
        struct WrittenInPlacePart: View {
            var body: some View {
                WebView()
                    .source(html: "<h2>Written in place</h2><p>No network involved.</p>")
            }
        }
        """

    var body: some View {
        WebView()
            .source(html: "<h2>Written in place</h2><p>No network involved.</p>")
    }

    var notes: (any View)? {
        Text("`source(html:)` shows HTML written in place, without the network. Web "
            + "content scrolls itself, which is why this page holds still and the view "
            + "fills the height the window gives it.")
            .font(.system(size: 12))
            .foregroundStyle(Palette.subtle)
    }
}
