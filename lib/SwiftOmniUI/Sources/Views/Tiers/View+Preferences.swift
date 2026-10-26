// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// Preferences: values a view writes for its ancestors, folded by each key's
// `reduce` as they climb - `.preference` and `.anchorPreference` write,
// `.transformPreference` rewrites, `.onPreferenceChange` and the
// `*PreferenceValue` backgrounds read back.
// Design: docs/design/core/identity-and-diffing.md#preferences

extension View {
    /// Writes `value` for `key` on this view, offered to its ancestors along
    /// with its subtree's own writes, folded by the key's `reduce` on the way.
    ///
    ///     .preference(key: LayoutKey.self, value: [block])
    ///
    /// - Parameters:
    ///   - key: Which preference to write.
    ///   - value: The value offered.
    public func preference<K: PreferenceKey>(
        key: K.Type = K.self, value: K.Value
    ) -> ModifiedContent {
        revised {
            $0.preferenceSeeds.append(PreferenceSeed(box: PreferenceKeyBox(K.self), value: value))
        }
    }

    /// Rewrites what this view's subtree answers `key` before its ancestors
    /// fold it - the value passes through `transform` once.
    ///
    /// - Parameters:
    ///   - key: Which preference to rewrite.
    ///   - transform: The rewrite of the folded value.
    public func transformPreference<K: PreferenceKey>(
        _ key: K.Type = K.self,
        _ transform: @escaping (K.Value) -> K.Value
    ) -> ModifiedContent {
        revised {
            $0.preferenceTransforms.append(PreferenceTransform(box: PreferenceKeyBox(K.self)) { value in
                (value as? K.Value).map(transform) ?? value
            })
        }
    }

    /// Writes `transform` of an anchor into this view for `key`, as
    /// `.preference` writes a plain value - the anchor resolving against a
    /// `GeometryProxy` when a reader asks for it:
    ///
    ///     .anchorPreference(key: LayoutKey.self, value: .bounds) { bounds in
    ///         [MarkdownLayout(blockId: blockId, bounds: bounds)]
    ///     }
    ///
    /// The anchored view reports its frame to keep the anchor's answer
    /// current.
    ///
    /// - Parameters:
    ///   - key: Which preference to write.
    ///   - value: Which part of this view the anchor watches.
    ///   - transform: What the anchor becomes - usually a value holding it.
    public func anchorPreference<K: PreferenceKey, A>(
        key: K.Type = K.self,
        value: AnchorSource<A>,
        transform: @escaping (Anchor<A>) -> K.Value
    ) -> ModifiedContent {
        let box = AnchorBox()
        let anchor: Anchor<A>

        switch value.kind {
        case .bounds:
            // `.bounds` is the only source kind; the read makes a `Rect`, and
            // `A` is `Rect` wherever this case runs - the cast holds.
            anchor = Anchor<A>(box: box) { frame, reader in
                // swiftlint:disable:next force_cast
                Rect(frame.x - reader.x, frame.y - reader.y, frame.width, frame.height) as! A
            }
        }

        return revised { node in
            // The host's own frame reports keep the anchor's answer current.
            node.anchorBoxes.append(box)
            node.addHandler(.frameChanged) {
                guard let numbers = MemberValues.carried(
                    EventBuffer.current, by: "frameChanged", as: [Double].self),
                    let report = FrameReport(numbers)
                else { return }
                box.update(report)
            }
            node.preferenceSeeds.append(PreferenceSeed(
                box: PreferenceKeyBox(K.self), value: transform(anchor)))
        }
    }

    /// Runs `action` when the value this view's subtree answers `key` moves -
    /// and once when the view first mounts, telling the value it found.
    ///
    ///     .onPreferenceChange(LayoutWidthKey.self) { width in
    ///         detectedWidth = width
    ///     }
    ///
    /// - Parameters:
    ///   - key: Which preference to hear.
    ///   - action: What runs with the folded value, old against new inside.
    public func onPreferenceChange<K: PreferenceKey>(
        _ key: K.Type = K.self,
        perform action: @escaping (K.Value) -> Void
    ) -> ModifiedContent {
        revised {
            $0.preferenceObservers.append(PreferenceObserver(box: PreferenceKeyBox(K.self)) { _, new in
                guard let new = new as? K.Value else { return }
                action(new)
            })
        }
    }

    /// Draws `transform` of the folded `key` value behind this view -
    /// `GeometryReader` inside reads the anchors it collected:
    ///
    ///     content
    ///         .backgroundPreferenceValue(LayoutKey.self) { layouts in
    ///             GeometryReader { proxy in
    ///                 Color.clear.task(id: layouts) {
    ///                     resolve(proxy[layouts[0].bounds])
    ///                 }
    ///             }
    ///         }
    ///
    /// The background builds with `defaultValue` before the first fold lands,
    /// then again whenever the answer moves.
    ///
    /// - Parameters:
    ///   - key: Which preference to read.
    ///   - transform: What to draw behind, given the folded value.
    public func backgroundPreferenceValue<K: PreferenceKey, Content: View>(
        _ key: K.Type = K.self,
        @ViewBuilder transform: @escaping (K.Value) -> Content
    ) -> some View {
        PreferenceBacked(base: self, key: key, over: false, transform: transform)
    }

    /// The same value drawn over this view instead of behind it.
    ///
    /// - Parameters:
    ///   - key: Which preference to read.
    ///   - transform: What to draw over, given the folded value.
    public func overlayPreferenceValue<K: PreferenceKey, Content: View>(
        _ key: K.Type = K.self,
        @ViewBuilder transform: @escaping (K.Value) -> Content
    ) -> some View {
        PreferenceBacked(base: self, key: key, over: true, transform: transform)
    }
}

/// The composed view a `*PreferenceValue` modifier makes: the base wearing an
/// observer that writes the folded answer into a state the layer reads, so
/// the layer builds again whenever the answer moves - as `GeometryReader`
/// rebuilds from its frame reports.
private struct PreferenceBacked<K: PreferenceKey, Base: View, Content: View>: View {
    /// The last folded answer, `K.defaultValue` until the first fold lands.
    @State private var value: K.Value

    /// The view the layer stands against.
    let base: Base

    /// Whether the layer draws over the base rather than behind it.
    let over: Bool

    /// What the layer is, given the answer.
    let transform: (K.Value) -> Content

    /// The reader of `key` over `base`.
    init(
        base: Base, key: K.Type, over: Bool,
        transform: @escaping (K.Value) -> Content
    ) {
        self.base = base
        self.over = over
        self.transform = transform
        _value = State(wrappedValue: K.defaultValue)
    }

    var body: some View {
        let heard = base.revised { node in
            if ObjectIdentifier(K.self) == ObjectIdentifier(Text.LayoutKey.self) {
                node.writeInherited(TextContract.reportsLayout, true)
            }
        }.onPreferenceChange(K.self) { value = $0 }
        return Group {
            if over {
                heard.overlay { PreferenceLayer<K, Content>(value: $value, transform: transform) }
            } else {
                heard.background { PreferenceLayer<K, Content>(value: $value, transform: transform) }
            }
        }
    }
}

/// A preference change invalidates the dependent layer, not the base that produced it.
/// In particular, publishing a newly visible Text.Layout must not rebuild a lazy document's
/// row source (and its Markdown bodies) just to update a selection overlay.
private struct PreferenceLayer<K: PreferenceKey, Content: View>: View {
    let value: Binding<K.Value>
    let transform: (K.Value) -> Content

    var body: some View { transform(value.wrappedValue) }
}
