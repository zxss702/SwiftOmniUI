// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// `Picker`'s own properties, shared by the control and its `Style<Picker>`.
public protocol PickerProperties: PropertyContainer {}

extension PickerProperties {
    /// Shows or dismisses the list of choices. The user may still close it by
    /// choosing, clicking away or pressing Escape, which `onClosed` reports.
    @_spi(Host) public func isOpen(_ value: Bool) -> Modified {
        setValue(PickerContract.isOpen, value)
    }

    /// The captions to choose from, in order. Choosing among models, format
    /// them here and find the chosen one by its index.
    @_spi(Host) public func options(_ value: [String]) -> Modified {
        setValue(PickerContract.options, value)
    }

    /// Which item is chosen, counted from zero; -1 for none.
    @_spi(Host) public func selectedIndex(_ value: Int) -> Modified {
        setValue(PickerContract.selectedIndex, value)
    }

    /// What the field says while nothing is chosen. A host can also reuse it
    /// as the heading of a separate native choice surface.
    @_spi(Host) public func title(_ value: String) -> Modified {
        setValue(PickerContract.title, value)
    }
}

/// One choice out of a list.
///
///     private let sizes = ["Small", "Medium", "Large"]
///     @State private var size = 1
///
///     Picker(sizes)
///         .selectedIndex($size)
///         .title("Size")
///
/// The choice comes back through the binding as an index into the list, `-1`
/// while nothing is chosen; `sizes[size]` turns it back into a value, which is
/// why the list is worth holding. The picker takes `.foregroundStyle` but has no
/// `.text`: the field shows the chosen item or the title.
public struct Picker: VisualElement, TextStyleElement, FontElement, TextAlignmentElement, TintElement, PickerProperties{
    /// The node this control describes.
    public var node: Node

    /// An empty one - what a `Style<Picker>` is written against.
    public init() {
        node = Node(contract: PickerContract.self)
    }

    /// A picker offering `items`, with nothing chosen until `.selectedIndex`
    /// says so.
    public init(_ items: [String]) {
        node = Node(contract: PickerContract.self)
        node.write(PickerContract.options, items)
    }

    /// A picker of tagged choices - the SwiftUI spelling:
    ///
    ///     Picker("Branch", selection: $branch) {
    ///         ForEach(branches, id: \.self) { Text($0).tag($0) }
    ///     }
    ///
    /// Each child's `.tag` names its choice, its `Text` the words it shows -
    /// a child with no tag is named by its own words. The picker's
    /// `selectedIndex` follows `selection`, and a choice the user makes is
    /// written back into it. A selection naming no choice shows none.
    ///
    /// - Parameters:
    ///   - title: what the field says while nothing is chosen.
    ///   - selection: the chosen value, borrowed two-way.
    ///   - content: the choices, tagged.
    public init<Selection: Hashable & HostRepresentable, Content: View>(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title.displayString, key: title, selection: selection, content: content)
    }

    /// The same, its title verbatim - a `String` is never looked up.
    @_disfavoredOverload public init<Selection: Hashable & HostRepresentable, S: StringProtocol, Content: View>(
        _ title: S,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        self.init(String(title), key: nil, selection: selection, content: content)
    }

    /// The shared building of the tagged forms: `title` shown verbatim, `key`
    /// carried for the host's tables where one came in.
    private init<Selection: Hashable & HostRepresentable, Content: View>(
        _ title: String,
        key: LocalizedStringKey?,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) {
        var options: [String] = []
        var tags: [PropValue] = []
        let tagProp = Prop.tag, textProp = Prop.text

        for child in content().node.asChildren {
            let tag = child.props[tagProp] ?? child.props[textProp] ?? .nothing
            tags.append(tag)
            options.append(child.props[textProp]?.string ?? tag.string ?? tag.name ?? "")
        }

        self.init(options)
        node.write(PickerContract.title, title)
        if let key { node.write(PickerContract.titleKey, key) }
        node.write(
            PickerContract.selectedIndex,
            tags.firstIndex(of: selection.wrappedValue.propValue) ?? -1)

        self = onSelectedIndexChanged { index in
            guard tags.indices.contains(index),
                  let value = Selection(propValue: tags[index]) else { return }
            selection.wrappedValue = value
        }
    }

    // MARK: Properties

    // Design: docs/design/views/bindings.md#two-way-controls
    /// Two-way: shows the choice the state holds and writes back the one the
    /// user makes, with no view rebuilt for it.
    ///
    /// - Parameter binding: the state shown, and written back into as the
    ///   user chooses.
    /// - Returns: the picker, wearing and reporting that choice.
    @_spi(Host) public func selectedIndex(_ binding: Binding<Int>) -> Self {
        binding.image == nil
            ? described(.selectedIndex, binding, on: .selectedIndexChanged)
            : plain(.selectedIndex, by: binding, mode: .inOut)
    }

    // MARK: Events

    /// Fires when the user changes the choice, with the new index - after the
    /// choice has landed on a state handed as `$size`.
    @_spi(Host) public func onSelectedIndexChanged(_ handler: @escaping ValueEventHandler<Int>) -> Self {
        onEvent(PickerContract.selectedIndexChanged, handler)
    }

    /// The user has opened the list of choices. Opening it with `isOpen(true)`
    /// raises nothing: the application already knows.
    @_spi(Host) public func onOpened(_ handler: @escaping EventHandler) -> Self {
        onEvent(PickerContract.opened, handler)
    }

    /// The user has closed it - by a choice, a click outside or the platform's
    /// own dismissal.
    @_spi(Host) public func onClosed(_ handler: @escaping EventHandler) -> Self {
        onEvent(PickerContract.closed, handler)
    }
}
