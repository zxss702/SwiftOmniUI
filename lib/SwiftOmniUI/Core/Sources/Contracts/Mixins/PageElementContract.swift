// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// What a page shows about itself where another container presents it as an
/// item - a title and a picture. A page and an arrangement say them under the
/// same keys, so both wear this tier, and it wears nothing: a page carries its
/// title and its icon, and no other value an element carries.
public enum PageElementContract: Contract {
    /// The tier's name.
    public static let name = "PageElement"

    /// The picture shown with the title - a tab's icon.
    public static let icon = ElementProperty<Self, ImageSource>("icon", layer: .adaptive)

    /// The title.
    public static let title = ElementProperty<Self, String>("title", layer: .native)

    /// The title as a lookup key, as `TextElementContract.textKey` is for
    /// the elements that wear it.
    public static let titleKey = ElementProperty<Self, LocalizedStringKey>(
        "titleKey", layer: .native, travels: false)

    /// The mark the item wears on its icon - a count, a dot - as its container
    /// draws it.
    public static let badge = ElementProperty<Self, String>("badge", layer: .native)

    /// The heights a presented page may stand at, first the one preferred.
    public static let presentationDetents = ElementProperty<Self, [PresentationDetent]>(
        "presentationDetents", layer: .native)

    /// Whether a presented page shows its drag handle.
    public static let presentationDragIndicator = ElementProperty<Self, Visibility>(
        "presentationDragIndicator", layer: .native)

    /// Whether the user may not dismiss a presented page.
    public static let interactiveDismissDisabled = ElementProperty<Self, Bool>(
        "interactiveDismissDisabled", layer: .native)

    /// A second line naming the current document or section, shown in the
    /// title area where the platform takes one.
    public static let subtitle = ElementProperty<Self, String>("subtitle", layer: .adaptive)

    /// The subtitle as a lookup key, as `titleKey` is for the title.
    public static let subtitleKey = ElementProperty<Self, LocalizedStringKey>(
        "subtitleKey", layer: .native, travels: false)

    /// The path of the document the page stands for, where a platform shows
    /// one in its window's chrome.
    public static let document = ElementProperty<Self, String>("document", layer: .adaptive)

    /// The width a split view's column prefers, as least, ideal and most -
    /// a single number for a fixed width.
    public static let preferredColumnWidth = ElementProperty<Self, [Double]>(
        "preferredColumnWidth", layer: .adaptive)

    /// Whether the window's own toolbar shows over the page.
    public static let toolbarVisibility = ElementProperty<Self, Visibility>(
        "toolbarVisibility", layer: .adaptive)

    /// Whether the window's own toolbar paints its background.
    public static let toolbarBackground = ElementProperty<Self, Visibility>(
        "toolbarBackground", layer: .adaptive)

    /// The colour the window paints behind the page's own background.
    public static let windowBackground = ElementProperty<Self, Color>(
        "windowBackground", layer: .adaptive)

    /// The tier's own members.
    public static let members: [any ContractMember] = [
        badge, document, icon, interactiveDismissDisabled, preferredColumnWidth, presentationDetents,
        presentationDragIndicator, subtitle, subtitleKey, title, titleKey, toolbarBackground,
        toolbarVisibility,
        windowBackground,
    ]
}
