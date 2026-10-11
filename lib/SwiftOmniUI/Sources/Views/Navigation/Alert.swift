// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.alert`: the platform's own dialog, driven by a bool - an act asked of the
// page that is showing.
// Design: docs/design/core/acts.md#dialogs

extension View {
    /// Presents the platform's alert while `isPresented` holds.
    ///
    ///     .alert("Sign in", isPresented: $failed) {
    ///         Button("OK", role: .cancel) {}
    ///     } message: {
    ///         Text("The token was refused.")
    ///     }
    ///
    /// The buttons are the views in `actions`: a `Button`'s caption names the
    /// choice and its action runs when it is pressed; a `.cancel` role
    /// dismisses and a `.destructive` role is marked dangerous. One cancel
    /// button is an announcement, one choice beside it a confirmation, and
    /// more an action list - the platform draws each as its own dialog.
    /// Answering writes `isPresented` back to false, whichever button took it.
    ///
    /// - Parameters:
    ///   - title: what the alert is about.
    ///   - isPresented: whether it is up, both ways.
    ///   - actions: the buttons to offer.
    ///   - message: the text under the title.
    @_disfavoredOverload public func alert<Actions: View, Message: View, S: StringProtocol>(
        _ title: S,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        AlertAnchor(
            base: self, title: String(title), titleKey: nil, presented: isPresented,
            actions: actions, message: message)
    }

    /// The same, its title and captions looked up - a literal is a key the
    /// host answers, as `Text(_ key:)` is:
    ///
    ///     .alert("Sign in", isPresented: $failed) { … } message: { … }
    public func alert<Actions: View, Message: View>(
        _ titleKey: LocalizedStringKey,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        AlertAnchor(
            base: self, title: titleKey.displayString, titleKey: titleKey,
            presented: isPresented, actions: actions, message: message)
    }
}

/// The anchor `.alert` leaves in the tree: the view it was written on, plus a
/// watch that asks the dialog act when the binding turns up.
struct AlertAnchor<Actions: View, Message: View>: View {
    /// The view `.alert` was written on.
    let base: any View

    /// What the alert is about.
    let title: String

    /// The title's lookup key, where one came in - resolved as the act goes
    /// out.
    let titleKey: LocalizedStringKey?

    /// Whether the alert is up.
    let presented: Binding<Bool>

    /// The buttons, as views.
    let actions: () -> Actions

    /// The message, as views.
    let message: () -> Message

    /// Guards a re-entry while the act is out: a bool flipping twice, a
    /// presented alert must not be asked again.
    @State private var asking = false

    var body: some View {
        base
            .onChange(of: presented.wrappedValue) { _, shown in
                guard shown, !asking else { return }
                asking = true
                defer { asking = false }
                do {
                    try await ask()
                } catch {
                    // No page to ask of, or the host could not: the answer
                    // is the alert is not up.
                }
                presented.wrappedValue = false
            }
    }

    /// The buttons the actions describe, in the order they were written.
    private var buttons: [AlertButton] {
        var found: [AlertButton] = []
        collectButtons(in: actions().node.built, into: &found)
        return found
    }

    /// The message's words: the first text the message describes.
    private var messageText: String {
        words(in: message().node.built) ?? ""
    }

    /// Asks the dialog the buttons amount to, then runs the pressed one's
    /// action - the answer reaching nobody runs nothing.
    @MainActor func ask() async throws {
        let heading = if let titleKey { await Strings.localize(titleKey) } else { title }
        let note = if let messageKey { await Strings.localize(messageKey) } else { messageText }
        var names: [String] = []
        for button in buttons {
            if let key = button.key {
                names.append(await Strings.localize(key))
            } else {
                names.append(button.title)
            }
        }
        let cancels = buttons.indices.filter { buttons[$0].role == .cancel }
        let pressed: String?
        if buttons.count <= 1, let cancel = cancels.first ?? buttons.indices.first {
            try await Dialogs.alert(heading, message: note, cancel: names[cancel])
            pressed = names[cancel]
        } else if buttons.count == 2, let cancel = cancels.first,
                  let accept = buttons.indices.first(where: { buttons[$0].role != .cancel }) {
            let yes = try await Dialogs.confirm(
                heading, message: note, accept: names[accept], cancel: names[cancel])
            pressed = yes ? names[accept] : names[cancel]
        } else {
            pressed = try await Dialogs.chooseAction(
                heading,
                cancel: cancels.first.map { names[$0] },
                destruction: buttons.indices.first { buttons[$0].role == .destructive }
                    .map { names[$0] },
                buttons: buttons.indices.filter { buttons[$0].role == .normal }.map { names[$0] })
        }
        if let pressed, let chosen = names.firstIndex(of: pressed) {
            try await buttons[chosen].handler?()
        }
    }

    /// The message's lookup key, where its first text carried one.
    private var messageKey: LocalizedStringKey? {
        key(in: message().node.built)
    }

    /// The words a button or a text carries, the key them, and the role
    /// marking a button.
    private var textProp: Prop { Prop("text") }
    private var keyProp: Prop { Prop("textKey") }
    private var roleProp: Prop { Prop("role") }

    /// One button extracted from the actions: its caption, its mark and what
    /// it does.
    private struct AlertButton {
        let title: String
        let key: LocalizedStringKey?
        let role: ButtonRole
        let handler: EventHandler?
    }

    /// Every `Button` the node stands for, in the order it stands.
    private func collectButtons(in node: Node, into found: inout [AlertButton]) {
        if node.type.name == "Button", let title = node.props[textProp]?.string {
            let role = node.props[roleProp].flatMap(ButtonRole.init(propValue:)) ?? .normal
            let key = node.props[keyProp].flatMap(LocalizedStringKey.init(propValue:))
            found.append(AlertButton(title: title, key: key, role: role, handler: node.events[Event("clicked")]))
        }
        for child in node.children { collectButtons(in: child, into: &found) }
    }

    /// The first view's words the node stands for.
    private func words(in node: Node) -> String? {
        if ["Text", "Label"].contains(node.type.name), let words = node.props[textProp]?.string {
            return words
        }
        return node.children.lazy.compactMap(words).first
    }

    /// The first view's lookup key the node stands for.
    private func key(in node: Node) -> LocalizedStringKey? {
        if ["Text", "Label"].contains(node.type.name) {
            return node.props[keyProp].flatMap(LocalizedStringKey.init(propValue:))
        }
        return node.children.lazy.compactMap(key).first
    }
}
