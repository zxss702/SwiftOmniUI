// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What the view says about itself.
// Design: docs/design/views/modifiers.md#accessibility-and-automation

extension VisualElementProperties {
    /// What a screen reader says this view is.
    ///
    ///     Button(icon: "bin.png").accessibilityLabel("Delete")
    ///
    /// For a control whose meaning is carried by a picture, a colour or where
    /// it sits. On a control that shows its own words it replaces them.
    public func accessibilityLabel(_ value: String) -> Modified { setValue(VisualElementContract.accessibilityLabel, value) }

    /// What a screen reader says using the view does, after saying what it is.
    ///
    ///     Switch($lit)
    ///         .accessibilityLabel("Ceiling light")
    ///         .accessibilityHint("Turns the light on and off")
    ///
    /// Only for a view the user can act on.
    public func accessibilityHint(_ value: String) -> Modified { setValue(VisualElementContract.accessibilityHint, value) }

    /// Whether a screen reader skips this view.
    ///
    ///     ColorPicker(.silver).accessibilityHidden(true)
    ///
    /// For decoration: a rule, a shadow, a picture repeating the words beside
    /// it. Left unsaid, the platform decides, which is nearly always right; say
    /// `false` where a platform left something out, and never hide a view the
    /// user has to act on.
    public func accessibilityHidden(_ value: Bool) -> Modified { setValue(VisualElementContract.isAccessibilityHidden, value) }

    /// The member's own spelling, kept for code that already says it.
    @_spi(Host) public func isAccessibilityHidden(_ value: Bool) -> Modified { accessibilityHidden(value) }

    /// Whether a screen reader skips this view and everything inside it.
    ///
    ///     VStack { … }.automationExcludedWithChildren(true)
    ///
    /// For a panel on screen that is not the user's business - a decorative
    /// header, a card standing behind the one in front.
    @_spi(Host) public func automationExcludedWithChildren(_ value: Bool) -> Modified { setValue(VisualElementContract.automationExcludedWithChildren, value) }

    /// That this view is a heading, and how deep.
    ///
    ///     Text("Settings").fontSize(24).accessibilityHeadingLevel(.level1)
    ///
    /// A screen-reader user moves through a long page by its headings; a Text
    /// drawn big is not one until this says so.
    @_spi(Host) public func accessibilityHeadingLevel(_ value: HeadingLevel) -> Modified { setValue(VisualElementContract.accessibilityHeadingLevel, value) }

    /// The tip the platform shows under a pointer resting on the view:
    ///
    ///     Button("Crop").help("Cuts the picture to what is selected")
    ///
    /// A literal is a key the host answers; a `String` variable stays the
    /// words it is - the `View` form says them, this one says the key beside
    /// its `displayString` fallback.
    public func help(_ key: LocalizedStringKey) -> Modified {
        modified {
            $0.props[VisualElementContract.hint.token] = key.displayString.propValue
            $0.props[VisualElementContract.hintKey.token] = key.propValue
        }
    }
}

extension VisualElementProperties {
    /// `accessibilityIdentifier` from a state, `$x`: the host writes each new
    /// text, and no view is rebuilt for it.
    public func accessibilityIdentifier(_ state: Binding<String>) -> Modified {
        words(PropertyContainerContract.accessibilityIdentifier, by: state)
    }

    /// `automationExcludedWithChildren` from a state, `$x`: the host sets each
    /// new value as it stands, and no view is rebuilt for it.
    @_spi(Host) public func automationExcludedWithChildren(_ state: Binding<Bool>) -> Modified {
        plain(VisualElementContract.automationExcludedWithChildren, by: state)
    }

    /// `accessibilityHidden` from a state, `$x`: the host sets each new value
    /// as it stands, and no view is rebuilt for it.
    public func accessibilityHidden(_ state: Binding<Bool>) -> Modified {
        plain(VisualElementContract.isAccessibilityHidden, by: state)
    }

    /// The member's own spelling, kept for code that already says it.
    @_spi(Host) public func isAccessibilityHidden(_ state: Binding<Bool>) -> Modified {
        accessibilityHidden(state)
    }

    /// `accessibilityLabel` from a state, `$x`: the host writes each new text,
    /// and no view is rebuilt for it.
    public func accessibilityLabel(_ state: Binding<String>) -> Modified {
        words(VisualElementContract.accessibilityLabel, by: state)
    }

    /// `accessibilityHeadingLevel` from a state, `$x`: the host sets each new
    /// value as it stands, and no view is rebuilt for it.
    @_spi(Host) public func accessibilityHeadingLevel(_ state: Binding<HeadingLevel>) -> Modified {
        plain(VisualElementContract.accessibilityHeadingLevel, by: state)
    }

    /// `accessibilityHint` from a state, `$x`: the host writes each new text,
    /// and no view is rebuilt for it.
    public func accessibilityHint(_ state: Binding<String>) -> Modified {
        words(VisualElementContract.accessibilityHint, by: state)
    }

    /// `help` from a state, `$x`: the host writes each new text, and no view is
    /// rebuilt for it.
    public func help(_ state: Binding<String>) -> Modified {
        words(VisualElementContract.hint, by: state)
    }
}

extension View {
    /// The name an automation test or the inspector finds this view by.
    ///
    ///     Button("Save").accessibilityIdentifier("save")
    @_disfavoredOverload
    public func accessibilityIdentifier(_ value: String) -> ModifiedContent { setting(PropertyContainerContract.accessibilityIdentifier, value) }

    /// What a screen reader says this view is.
    @_disfavoredOverload
    public func accessibilityLabel(_ value: String) -> ModifiedContent { setting(VisualElementContract.accessibilityLabel, value) }

    /// What a screen reader says using the view does, after saying what it is.
    @_disfavoredOverload
    public func accessibilityHint(_ value: String) -> ModifiedContent { setting(VisualElementContract.accessibilityHint, value) }

    /// Whether a screen reader skips this view.
    @_disfavoredOverload
    public func accessibilityHidden(_ value: Bool) -> ModifiedContent { setting(VisualElementContract.isAccessibilityHidden, value) }

    /// Whether a screen reader skips this view and everything inside it.
    @_disfavoredOverload
    @_spi(Host) public func automationExcludedWithChildren(_ value: Bool) -> ModifiedContent { setting(VisualElementContract.automationExcludedWithChildren, value) }

    /// That this view is a heading, and how deep.
    @_disfavoredOverload
    @_spi(Host) public func accessibilityHeadingLevel(_ value: HeadingLevel) -> ModifiedContent { setting(VisualElementContract.accessibilityHeadingLevel, value) }

    /// Adds to what a screen reader says this view is and does.
    ///
    ///     row.accessibilityAddTraits(selected ? .isSelected : [])
    @_disfavoredOverload
    public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> ModifiedContent {
        revised {
            let standing = AccessibilityTraits(
                rawValue: $0.props[VisualElementContract.accessibilityTraits.token]?.enumeration ?? 0)
            $0.props[VisualElementContract.accessibilityTraits.token] = standing.union(traits).propValue
        }
    }

    /// Takes away part of what a screen reader says this view is and does.
    @_disfavoredOverload
    public func accessibilityRemoveTraits(_ traits: AccessibilityTraits) -> ModifiedContent {
        revised {
            let standing = AccessibilityTraits(
                rawValue: $0.props[VisualElementContract.accessibilityTraits.token]?.enumeration ?? 0)
            $0.props[VisualElementContract.accessibilityTraits.token] = standing.subtracting(traits).propValue
        }
    }

    /// How this view's children take part in accessibility: `.ignore` leaves
    /// only the view itself, `.combine` merges them into it, `.contain` lets
    /// each stand on its own.
    ///
    ///     VStack { dots }.accessibilityElement(children: .ignore)
    @_disfavoredOverload
    public func accessibilityElement(children: AccessibilityChildBehavior) -> ModifiedContent {
        setting(VisualElementContract.accessibilityChildBehavior, children)
    }

    /// The tip the platform shows under a pointer resting on the view.
    @_disfavoredOverload
    public func help(_ value: some StringProtocol) -> ModifiedContent {
        setting(VisualElementContract.hint, String(value))
    }

    /// The same, looked up - the key beside its `displayString` fallback.
    @_disfavoredOverload
    public func help(_ key: LocalizedStringKey) -> ModifiedContent {
        setting(VisualElementContract.hint, key.displayString)
            .setting(VisualElementContract.hintKey, key)
    }
}

extension View {
    /// `accessibilityIdentifier` from a state, `$x`: the host writes each new
    /// text, and no view is rebuilt for it.
    @_disfavoredOverload
    public func accessibilityIdentifier(_ state: Binding<String>) -> ModifiedContent {
        revised { $0.driveWords(PropertyContainerContract.accessibilityIdentifier, by: state) }
    }

    /// `automationExcludedWithChildren` from a state, `$x`: the host sets each
    /// new value as it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func automationExcludedWithChildren(_ state: Binding<Bool>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.automationExcludedWithChildren, by: state) }
    }

    /// `accessibilityHidden` from a state, `$x`: the host sets each new value
    /// as it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    public func accessibilityHidden(_ state: Binding<Bool>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.isAccessibilityHidden, by: state) }
    }

    /// `accessibilityLabel` from a state, `$x`: the host writes each new text,
    /// and no view is rebuilt for it.
    @_disfavoredOverload
    public func accessibilityLabel(_ state: Binding<String>) -> ModifiedContent {
        revised { $0.driveWords(VisualElementContract.accessibilityLabel, by: state) }
    }

    /// `accessibilityHeadingLevel` from a state, `$x`: the host sets each new
    /// value as it stands, and no view is rebuilt for it.
    @_disfavoredOverload
    @_spi(Host) public func accessibilityHeadingLevel(_ state: Binding<HeadingLevel>) -> ModifiedContent {
        revised { $0.drivePlain(VisualElementContract.accessibilityHeadingLevel, by: state) }
    }

    /// `help` from a state, `$x`: the host writes each new text, and no view is
    /// rebuilt for it.
    @_disfavoredOverload
    public func help(_ state: Binding<String>) -> ModifiedContent {
        revised { $0.driveWords(VisualElementContract.hint, by: state) }
    }

    /// `accessibilityHint` from a state, `$x`: the host writes each new text,
    /// and no view is rebuilt for it.
    @_disfavoredOverload
    public func accessibilityHint(_ state: Binding<String>) -> ModifiedContent {
        revised { $0.driveWords(VisualElementContract.accessibilityHint, by: state) }
    }
}
