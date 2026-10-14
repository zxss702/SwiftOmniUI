// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Button`'s own properties, shared by the control and its `Style<Button>`.
public protocol ButtonProperties: PropertyContainer {}

extension ButtonProperties {
    /// What happens to a caption too long for the button.
    @_spi(Host) public func lineBreak(_ value: LineBreak) -> Modified {
        setValue(ButtonContract.lineBreak, value)
    }

    /// Where a too-long caption is cut, the SwiftUI spelling of the
    /// truncating `lineBreak`s.
    public func truncationMode(_ mode: TruncationMode) -> Modified {
        lineBreak(mode.lineBreak)
    }

    /// The picture beside the caption - a file among the application's image
    /// resources, by name; see `Image`. A button with an icon and no caption is
    /// `Button(icon:)`.
    ///
    ///     Button("Surprise me").icon("nav_surprise.png")
    @_spi(Host) public func icon(_ value: ImageSource) -> Modified {
        setValue(ButtonContract.icon, value)
    }

    /// Which side of the caption the icon stands on. `.leading`, the default,
    /// is the side a line of text starts from, so it follows the layout
    /// direction.
    ///
    ///     Button("Surprise me")
    ///         .icon("nav_surprise.png")
    ///         .iconPosition(.leading)
    ///         .iconSpacing(8)
    @_spi(Host) public func iconPosition(_ value: IconPosition) -> Modified {
        setValue(ButtonContract.iconPosition, value)
    }

    /// The gap between the icon and the caption, in device units.
    @_spi(Host) public func iconSpacing(_ value: Double) -> Modified {
        setValue(ButtonContract.iconSpacing, value)
    }
}

/// A button with a caption, and a handler for the press.
///
///     @State private var counter = 0
///     …
///     Button("Increment")
///         .background(.cornflowerBlue)
///         .shape(.roundedRectangle(8))
///         .onClicked { counter += 1 }
///
/// A handler runs on the main actor and may `await`; the interface goes on
/// updating while it is suspended, so `.onClicked { items = try await load() }`
/// needs nothing around it.
public struct Button: VisualElement, TextElement, FontElement, PaddingElement, BorderElement, ImageElement, ButtonProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<Button>` is written against.
    public init() {
        node = Node(contract: ButtonContract.self)
    }

    /// A button whose content is an icon, with no caption: the picture is what
    /// gives it its purpose.
    ///
    ///     Button(icon: "trash.png")
    ///     Button(icon: ImageSource(light: "trash.png", dark: "trash_dark.png"))
    ///
    /// The same button as one with a caption - the same outline, shape and
    /// pressed state - with `.aspect` for how its picture fills it.
    public init(icon: ImageSource) {
        node = Node(contract: ButtonContract.self)
        node.write(ButtonContract.icon, icon)
    }

    /// A button captioned `content`, verbatim - a `String` is never looked
    /// up; the literal that is a key is `Button(_ key:)`, which a literal
    /// prefers.
    @_disfavoredOverload public init<S: StringProtocol>(_ content: S) {
        node = Node(contract: ButtonContract.self)
        node.write(TextElementContract.text, String(content))
    }

    /// A button captioned what `key` looks up - `Button("Save")` looks "Save"
    /// up, as SwiftUI's does; `Button(someString)` shows it verbatim.
    public init(_ key: LocalizedStringKey) {
        node = Node(contract: ButtonContract.self)
        node.write(TextElementContract.text, key.displayString)
        node.write(TextElementContract.textKey, key)
    }

    /// A button whose caption is carried from a state, written by the host as
    /// it changes, at no render.
    ///
    /// - Parameter text: the state the caption is read from.
    public init(_ text: Binding<String>) {
        self = Button().text(text)
    }

    /// A button captioned `title`, marked as a destructive or a cancelling
    /// action where the platform marks one.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, role: ButtonRole) {
        self.init(title)
        node.write(ButtonContract.role, role)
    }

    /// A button captioned what `key` looks up, marked as a destructive or a
    /// cancelling action where the platform marks one.
    public init(_ key: LocalizedStringKey, role: ButtonRole) {
        self.init(key)
        node.write(ButtonContract.role, role)
    }

    /// A button captioned `title`, running `action` on a press - the SwiftUI
    /// spelling of `Button(title).onClicked(action)`.
    ///
    ///     Button("Save") { save() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping EventHandler) {
        self = Button(title).onClicked(action)
    }

    /// A button captioned what `key` looks up, running `action` on a press.
    public init(_ key: LocalizedStringKey, action: @escaping EventHandler) {
        self = Button(key).onClicked(action)
    }

    /// The same, marked as a destructive or a cancelling action where the
    /// platform marks one.
    public init(_ key: LocalizedStringKey, role: ButtonRole, action: @escaping EventHandler) {
        self = Button(key).onClicked(action)
        node.write(ButtonContract.role, role)
    }

    /// An icon button running `action` on a press.
    public init(icon: ImageSource, action: @escaping EventHandler) {
        self = Button(icon: icon).onClicked(action)
    }

    /// The same, marked as a destructive or a cancelling action where the
    /// platform marks one.
    ///
    ///     Button("Delete", role: .destructive) { remove() }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, role: ButtonRole, action: @escaping EventHandler) {
        self = Button(title).onClicked(action)
        node.write(ButtonContract.role, role)
    }

    /// A button whose label is a view - composed of it rather than the
    /// platform's captioned control: the label stands alone and a tap on it
    /// is the press.
    ///
    ///     Button { open(url) } label: { Label("Docs", systemImage: "book") }
    public init(action: @escaping EventHandler, @ViewBuilder label: () -> any View) {
        self.init()
        let content = ContentButton(action: action, label: label())
        node = Node.composed(content, type: "Button") { content.body.node }
    }

    /// The same, marked as a destructive or a cancelling action - the mark is
    /// a note the label may take, not a look the button imposes on it.
    public init(role: ButtonRole, action: @escaping EventHandler, @ViewBuilder label: () -> any View) {
        self.init(action: action, label: label)
        node.write(ButtonContract.role, role)
    }

    // MARK: Events

    /// Runs when the button is pressed AND released on it - the ordinary one.
    /// A second `.onClicked` runs beside the first, like every typed event
    /// modifier.
    @_spi(Host) public func onClicked(_ handler: @escaping EventHandler) -> Self {
        onEvent(ButtonContract.clicked, handler)
    }

    /// Runs the moment a press begins, before it ends.
    @_spi(Host) public func onPressed(_ handler: @escaping EventHandler) -> Self {
        onEvent(ButtonContract.pressed, handler)
    }

    /// Runs when the press ends, wherever the pointer ends up - unlike
    /// `onClicked`, which needs it to end on the button.
    @_spi(Host) public func onReleased(_ handler: @escaping EventHandler) -> Self {
        onEvent(ButtonContract.released, handler)
    }

    /// The staying-pressed look: worn at all the button keeps a press down
    /// and lets the next one up, each flip reported by `.onToggled`. What a
    /// `Toggle` in `.button` style is written with; for a button of your own,
    /// say `Toggle`.
    @_spi(Host) public func isOn(_ value: Bool) -> Modified {
        setValue(ButtonContract.isOn, value)
    }

    /// `isOn` from a state, `$x`: the host sets each new look as it stands.
    @_spi(Host) public func isOn(_ state: Binding<Bool>) -> Modified {
        plain(ButtonContract.isOn, by: state)
    }

    /// Runs as a staying-pressed button flips - `true` for now pressed.
    @_spi(Host) public func onToggled(_ handler: @escaping ValueEventHandler<Bool>) -> Self {
        onEvent(ButtonContract.toggled, handler)
    }
}

/// What a button does to what it touches, where the platform marks one.
/// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
/// Design: docs/design/types/vocabularies.md#written-out-and-appended
public enum ButtonRole: Int32, Sendable, HostRepresentable {
    /// An ordinary button - the default.
    case normal = 0

    /// Destroys what it touches - drawn warningly where the platform does.
    case destructive = 1

    /// Dismisses without acting - the Cancel a dialog offers.
    case cancel = 2
}

extension ButtonRole: StateChoice {}

/// What `Button(action:label:)` builds: the label, tapped - no caption, no
/// border of the platform's own, which a content button does not wear.
struct ToolbarContentKey: EnvironmentKey {
    static let defaultValue = false
}

struct MenuContentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isMenuContent: Bool {
        get { self[MenuContentKey.self] }
        set { self[MenuContentKey.self] = newValue }
    }
    var isToolbarContent: Bool {
        get { self[ToolbarContentKey.self] }
        set { self[ToolbarContentKey.self] = newValue }
    }
}

struct ContentButton: View {
    @Environment(\.isToolbarContent) private var isToolbarContent
    @Environment(\.isMenuContent) private var isMenuContent
    /// What a press runs.
    let action: EventHandler

    /// The label the button shows.
    let label: any View

    /// The label, answering a tap.
    var body: any View {
        if isMenuContent {
            var button = Button().onClicked(action)
            button.node.children = [label.node]
            return button
        }
        if isToolbarContent {
            let face = unwrappedStatement(label)
            if let label = face as? Label, let source = label.semanticParts.icon {
                let title = label.semanticParts.title?.display ?? ""
                var button = Button(icon: source).onClicked(action)
                button.node.children = [label.icon.node]
                return button.help(title)
            }
            if let image = face as? Image, let source = image.imageSource {
                var button = Button(icon: source).onClicked(action)
                button.node.children = [image.node]
                return button
            }
            // Words, or a view of the author's: still the bar's own button,
            // with the label as its face.
            var button = Button().onClicked(action)
            button.node.children = [label.node]
            return button
        }
        return label.onTapGesture(action)
    }
}

/// Which side of a button's caption its picture is on.
public enum IconPosition: Int32, Sendable, HostRepresentable {
    /// Before the words, on the side a line starts from - the default.
    case leading = 0

    /// Above them.
    case top = 1

    /// After them, on the side a line ends.
    case trailing = 2

    /// Below them.
    case bottom = 3
}

extension IconPosition: StateChoice {}

extension Button {
    /// `iconPosition` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func iconPosition(_ state: Binding<IconPosition>) -> Modified {
        plain(.iconPosition, by: state)
    }

    /// `iconSpacing` from a state, `$x`: the host animates the property to each
    /// new value, and no view is rebuilt for it.
    @_spi(Host) public func iconSpacing(_ state: Binding<Double>) -> Modified {
        journey(.iconSpacing, by: state)
    }

    /// `lineBreak` from a state, `$x`: the host sets each new value as it
    /// stands, and no view is rebuilt for it.
    @_spi(Host) public func lineBreak(_ state: Binding<LineBreak>) -> Modified {
        plain(ButtonContract.lineBreak.token, by: state)
    }
}
