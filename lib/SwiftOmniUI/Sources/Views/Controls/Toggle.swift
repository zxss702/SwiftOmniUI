// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// How a `Toggle` draws: the platform's usual control, or the one a
/// `.toggleStyle` above it chooses.
///
/// The automatic choice follows the device: a checkbox where windows stand
/// beside each other, a switch where one screen is shown at a time.
public final class ToggleStyle: @unchecked Sendable {
    /// The shape the toggle takes - one of `checkbox`, `switch`, `button` or
    /// automatic.
    enum Kind: Int32 {
        case automatic = 0
        case checkbox = 1
        case `switch` = 2
        case button = 3
    }

    /// The shape named.
    let kind: Kind

    private init(_ kind: Kind) { self.kind = kind }

    /// What the device calls for - a checkbox on a desktop, a switch elsewhere.
    public static let automatic = ToggleStyle(.automatic)

    /// A tick box, the shape a form uses.
    public static let checkbox = ToggleStyle(.checkbox)

    /// A sliding switch.
    public static let `switch` = ToggleStyle(.switch)

    /// A button that holds its pressed look while the toggle is on - a
    /// toolbar's, where each is one and any of them can be down at once.
    public static let button = ToggleStyle(.button)
}

/// An on/off control and the words beside it - a `CheckBox` where the desktop
/// is, a `Switch` on a phone or tablet, the choice overridable for a whole
/// branch with `.toggleStyle`:
///
///     Toggle("Sound", isOn: $soundOn)
///     Toggle(isOn: $quiet) { Image(.bellSlash) }
///
///     PreferencesView().toggleStyle(.checkbox)
///
/// Given a binding it shows the value and writes every flip back. Given a
/// plain `Bool` it only shows - a flip that must reach somewhere without a
/// binding is a `Switch` or `CheckBox` and its `.onToggled`.
public struct Toggle: View {
    /// The two-way state, or none for a control that only shows.
    let isOn: Binding<Bool>?

    /// What it shows where no binding is given.
    let initial: Bool

    /// The words, or `EmptyView` for a control alone.
    let label: any View

    /// The shape written above it with `.toggleStyle`, or automatic.
    @Environment private var style: ToggleStyle

    /// A toggle with its label made by the closure.
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> any View) {
        self.isOn = isOn
        self.initial = false
        self.label = label()
    }

    /// A toggle that only shows `isOn` - the flip reaches `.onToggled` on a
    /// `Switch` or `CheckBox`.
    public init(_ isOn: Bool, @ViewBuilder label: () -> any View) {
        self.isOn = nil
        self.initial = isOn
        self.label = label()
    }

    /// A toggle showing as unset, with its label - the flip reaches
    /// `.onToggled` on a `Switch` or `CheckBox`.
    public init(@ViewBuilder label: () -> any View) {
        self.init(false, label: label)
    }

    /// A toggle with its words - `Toggle("Sound", isOn: $soundOn)`.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(title) }
    }

    /// A toggle with its words looked up.
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) {
        self.init(isOn: isOn) { Text(titleKey) }
    }

    /// A one-way toggle with its words.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, isOn: Bool) {
        self.init(isOn) { Text(title) }
    }

    /// A one-way toggle with its words looked up.
    public init(_ titleKey: LocalizedStringKey, isOn: Bool) {
        self.init(isOn) { Text(titleKey) }
    }

    /// A one-way toggle with its words, showing as unset.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S) {
        self.init(false) { Text(title) }
    }

    /// A one-way toggle with its words looked up, showing as unset.
    public init(_ titleKey: LocalizedStringKey) {
        self.init(false) { Text(titleKey) }
    }

    /// The control alone, two-way.
    public init(isOn: Binding<Bool>) {
        self.init(isOn: isOn) { EmptyView() }
    }

    /// The control alone, showing `isOn`.
    public init(_ isOn: Bool) {
        self.init(isOn) { EmptyView() }
    }

    /// The control and its label: the device or the `.toggleStyle` above
    /// decides which control that is.
    public var body: some View {
        let kind = style.kind == .automatic
            ? (StandardEnvironment.device.formFactor == .phone
                || StandardEnvironment.device.formFactor == .tablet ? .switch : .checkbox)
            : style.kind

        return Group {
            if kind == .button {
                ToggleButton(isOn: isOn, initial: initial, label: label)
            } else if kind == .switch {
                HStack {
                    label
                    if let isOn { Switch(isOn) } else { Switch(initial) }
                }
                .spacing(8)
            } else {
                HStack {
                    if let isOn { CheckBox(isOn) } else { CheckBox(initial) }
                    label
                }
                .spacing(8)
            }
        }
    }
}

/// What `Toggle`'s `.button` shape builds: a `Button` element wearing
/// `isOn`, which a host draws as the platform's staying-pressed button - a
/// toolbar's. The label hands its words and picture over where it can - a
/// `Text`'s, an `Image`'s, a `Label`'s - and draws beside the button where
/// it cannot.
private struct ToggleButton: View {
    /// The two-way state, or none for a toggle that only shows.
    let isOn: Binding<Bool>?

    /// What it shows where no binding is given.
    let initial: Bool

    /// The toggle's label.
    let label: any View

    var body: some View {
        var button: Button.Modified = isOn.map(Button().isOn) ?? Button().isOn(initial)
        var label = label
        if let (text, key, icon) = label.buttonCaption {
            if let text { button = button.text(text) }
            if let key {
                button = button.modified { $0.props[TextElementContract.textKey.token] = key.propValue }
            }
            if let icon { button = button.icon(icon) }
            label = EmptyView()
        }
        let toggling = button.onEvent(ButtonContract.toggled) { isOn?.wrappedValue = $0 }
        return Group {
            if unwrappedStatement(label) is EmptyView {
                toggling
            } else {
                HStack {
                    toggling
                    label
                }
                .spacing(8)
            }
        }
    }
}

extension View {
    /// What of this view a captioned button can carry - a `Text`'s words and
    /// their lookup key, an `Image`'s picture, a `Label`'s all three - or
    /// `nil` where nothing carries, the view drawing beside the button then.
    fileprivate var buttonCaption: (text: String?, key: LocalizedStringKey?, icon: ImageSource?)? {
        let view = unwrappedStatement(self)
        if let text = view as? Text {
            return (text.node.props[.text]?.string, text.wordsKey, nil)
        }
        if let image = view as? Image {
            return (nil, nil, image.node.props[.source].flatMap(ImageSource.init(propValue:)))
        }
        if let label = view as? Label {
            let parts = label.semanticParts
            return parts.title != nil || parts.icon != nil
                ? (parts.title?.display, parts.title?.key, parts.icon) : nil
        }
        return nil
    }
}

extension View {
    /// How every `Toggle` in this branch draws - `.checkbox` or `.switch`,
    /// or back to `.automatic`, the device's own choice:
    ///
    ///     SettingsPane().toggleStyle(.checkbox)
    ///
    /// Written on a view above the toggles it shapes; the nearest one wins.
    public func toggleStyle(_ style: ToggleStyle) -> ModifiedContent {
        environment(style)
    }
}
