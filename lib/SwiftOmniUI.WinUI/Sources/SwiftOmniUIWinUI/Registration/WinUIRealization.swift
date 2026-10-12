// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// What this host realizes beyond its registry, whose export says the rest - the WinUI 3 column of the control
/// dictionary; a member is recorded once a test of this package covers it.
/// Design: docs/design/contracts/dictionary.md#marks
enum WinUIRealization {
    /// The entries this host realizes none of: those it shows as unsupported, and the parts of one.
    static let unrealized: Set<String> = [
        "Content", "GridRow", "LeadingContent", "Map", "Pin", "PositionIndicator", "TitleBar", "TrailingContent",
    ]

    /// The entries a backend realizes on this host - a package of its own, for a library WinUI does not ship - which
    /// the application's head registers: WebView2's web view. Realized none of until it is registered.
    static let backends: Set<String> = ["WebView"]

    /// What the running host realizes none of: what it never makes, and each backend no one registered.
    @MainActor static var unmade: Set<String> {
        unrealized.union(backends.subtracting(WinUIRegistrations.registry.realization.elements))
    }

    /// The entries this host presents with no view of their own - a span is a run of its label's words - so no
    /// tier's record reaches them: only a member the entry's own records name is realized.
    static let viewless: Set<String> = ["Span"]

    /// The entries Windows will not have; none.
    static let notPlanned: [String: String] = [:]

    /// Every record, the tiers' first.
    static let records: [HostRecord] = [
        // MARK: Tiers - a member every wearer realizes alike
        .complete("MenuItemElement", "clicked"),
        .complete("MenuItemElement", "isEnabled"),
        .complete("MenuItemElement", "text"),
        .complete("PageElement", "badge"),
        .complete("PageElement", "interactiveDismissDisabled"),
        .partial("PageElement", "presentationDetents", missing: "A WinUI sheet has no detents: the first one asked for alone sizes the card against its window."),
        .notPlanned("PageElement", "presentationDragIndicator", reason: "A WinUI sheet has no drag indicator."),
        .complete("PageElement", "title"),
        .notPlanned("VisualElement", "contentTransition",
            reason: "WinUI swaps a control's words with no transition yet."),
        .notPlanned("VisualElement", "matchedGeometry",
            reason: "WinUI's layout motion flies no matched child into place yet."),
        .notPlanned("VisualElement", "matchedGeometrySource",
            reason: "WinUI's layout motion flies no matched child into place yet."),
        .notPlanned("VisualElement", "symbolEffect",
            reason: "WinUI's icons are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectActive",
            reason: "WinUI's icons are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectOptions",
            reason: "WinUI's icons are painted, not animated as symbols."),
        .notPlanned("VisualElement", "symbolEffectValue",
            reason: "WinUI's icons are painted, not animated as symbols."),
        .notPlanned("VisualElement", "blendMode",
            reason: "WinUI composites every element normally; a blend pass over its own content draws nothing yet."),
        .complete("VisualElement", "hint"),
        .complete("VisualElement", "ignoresInput"),
        .complete("VisualElement", "layoutDirection"),
        .complete("VisualElement", "style"),
        .complete("View", "layoutPriority"),
        .partial("View", "horizontalGuide",
            missing: "WinUI's items name no text baseline: the baseline guides land on edges; the rest align."),
        .partial("View", "verticalGuide",
            missing: "WinUI's items name no text baseline: the baseline guides land on edges; the rest align."),
        .notPlanned("View", "pointerStyle",
            reason: "WinUI's ProtectedCursor is not wired to elements yet."),

        // MARK: Entries - a control's or a part's own
        .unrealized("ActivityIndicator", "ignoresInput", why: hitOnlyWherePainted),
        .partial("DatePicker", "format", missing: "WinUI writes \"D\" and \"d\" in the user's own way, and any other pattern as \"d\"."),
        .unrealized("Ellipse", "ignoresInput", why: hitOnlyWherePainted),
        .unrealized("List", "style", why: "No style can name an List: a style names its control by an "
            + "initializer that sets nothing, which a list of some items has not."),
        .unrealized("MenuButton", "style", why: "No style can name a MenuButton: the `Menu` view makes one, "
            + "and no `Menu()` means anything; its closed style vocabulary crosses as `.menuStyle`."),
        .complete("Menu", "isEnabled"),
        .complete("Menu", "text"),
        .complete("MenuButton", "isEnabled"),
        .complete("MenuButton", "menuIndicator"),
        .complete("MenuButton", "menuStyle"),
        .notPlanned("Text", "minimumScaleFactor",
            reason: "A TextBlock scale-factor pass is not wired to the property yet."),
        .partial("Text", "textRenderer",
            missing: "A native control draws the words itself: a renderer watching layout degrades to the default draw pass; its own draw never runs."),
        .partial("ProgressBar", "progressStyle",
            missing: "The bar WinUI draws is linear; `circular` falls back to it rather than the ring."),
        .partial("Image", "renderingMode",
            missing: "WinUI shows the picture as loaded; `template` does not retint it against the theme."),
        .unrealized("Image", "ignoresInput", why: hitOnlyWherePainted),
        .unrealized("Line", "ignoresInput", why: hitOnlyWherePainted),
        .complete("NavigationStack", "popped"),
        .complete("Page", "appearing"),
        .complete("Page", "background"),
        .complete("Page", "disappearing"),
        .complete("Page", "hasNavigationBar"),
        .complete("Page", "navigatedFrom"),
        .complete("Page", "navigatedTo"),
        .complete("Page", "navigatingFrom"),
        .complete("Page", "contentPadding"),
        .unrealized("Path", "ignoresInput", why: hitOnlyWherePainted),
        .unrealized("Polygon", "ignoresInput", why: hitOnlyWherePainted),
        .unrealized("Polyline", "ignoresInput", why: hitOnlyWherePainted),
        .complete("RadioButton", "groupName"),
        .unrealized("Rectangle", "ignoresInput", why: hitOnlyWherePainted),
        .complete("Scene", "activated"),
        .complete("Scene", "deactivated"),
        .complete("Scene", "destroying"),
        .complete("Scene", "stopped"),
        .complete("Scene", "windowClosed"),
        .complete("Scene", "windowRestored"),
        .complete("Span", "background"),
        .complete("Span", "characterSpacing"),
        .complete("Span", "fontAttributes"),
        .complete("Span", "fontFamily"),
        .complete("Span", "fontSize"),
        .complete("Span", "text"),
        .complete("Span", "textCase"),
        .complete("Span", "foregroundStyle"),
        .complete("Span", "textDecorations"),
        .complete("NavigationSplitView", "isSidebarVisible"),
        .complete("NavigationSplitView", "isSidebarVisibleChanged"),
        .complete("NavigationSplitView", "columnVisibility"),
        .complete("NavigationSplitView", "columnVisibilityChanged"),
        .complete("TabView", "currentPage"),
        .complete("TabView", "currentPageChanged"),
        .partial("TimePicker", "format", missing: "WinUI's time picker writes hours and minutes as the user's clock does, whatever the format asks: no seconds, no pattern."),
        .complete("ToolbarItem", "icon"),
        .complete("ToolbarItem", "placement"),
        .complete("ToolbarItem", "priority"),
        .complete("ToolbarSpacer", "placement"),
        .complete("ToolbarSpacer", "variant"),
        .notPlanned("WebView", "panTouchCount", reason: webViewTakesTheHand),
        .notPlanned("WebView", "panUpdated", reason: webViewTakesTheHand),
        .notPlanned("WebView", "panXChannel", reason: webViewTakesTheHand),
        .notPlanned("WebView", "panYChannel", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pinchUpdated", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pointerEntered", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pointerExited", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pointerMoved", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pointerPressed", reason: webViewTakesTheHand),
        .notPlanned("WebView", "pointerReleased", reason: webViewTakesTheHand),
        .notPlanned("WebView", "swipeDirection", reason: webViewTakesTheHand),
        .notPlanned("WebView", "swipeThreshold", reason: webViewTakesTheHand),
        .notPlanned("WebView", "swiped", reason: webViewTakesTheHand),
        .notPlanned("WebView", "tapCount", reason: webViewTakesTheHand),
        .notPlanned("WebView", "tapGesture", reason: webViewTakesTheHand),
        .complete("WindowScene", "activated"),
        .complete("WindowScene", "created"),
        .complete("WindowScene", "deactivated"),
        .complete("WindowScene", "destroying"),
        .complete("WindowScene", "floatsOnTop"),
        .complete("WindowScene", "height"),
        .complete("WindowScene", "hidesWhenInactive"),
        .complete("WindowScene", "isMaximizable"),
        .complete("WindowScene", "isMinimizable"),
        .complete("WindowScene", "isTranslucent"),
        .complete("WindowScene", "maximumHeight"),
        .complete("WindowScene", "maximumWidth"),
        .complete("WindowScene", "minimumHeight"),
        .complete("WindowScene", "minimumWidth"),
        .complete("WindowScene", "modalPopped"),
        .complete("WindowScene", "resumed"),
        .complete("WindowScene", "stopped"),
        .complete("WindowScene", "title"),
        .complete("WindowScene", "width"),
        .complete("WindowScene", "windowType"),
        .complete("WindowScene", "windowValue"),
        .complete("WindowScene", "x"),
        .complete("WindowScene", "y"),
    ]

    /// Why a drawing's press is not let through as the tree says.
    static let hitOnlyWherePainted = "WinUI hands a figure, a picture, a colour box and the activity ring only the "
        + "presses on what they paint: an empty one is never pressed, so there is nothing to let through."

    /// Why a web view hears none of the user's hand as a view does.
    static let webViewTakesTheHand = "WebView2 gives the user's hand to its page: listened to by WinUI, it ends the "
        + "process (fail-fast in Microsoft.UI.Xaml.Controls)."

    /// What WinUI's registry says it realizes: the export's content.
    @MainActor static var declaration: HostDeclaration {
        let registry = WinUIRegistrations.registry
        return HostDeclaration(
            realization: registry.realization, shared: registry.sharedNames,
            acts: (HostActs.performed + HostActs.files + [
                AppContract.persistSceneValue, CanvasContract.measureText, ListContract.scrollTo,
                ScrollViewContract.scrollToDescendant]
            ).map(\.name))
    }

    /// What WinUI realizes, member by member: these records before what its registry says.
    @MainActor static var register: HostRegister {
        HostRegister(records: records, unrealized: unmade, viewless: viewless, notPlanned: notPlanned).and(declaration)
    }
}
