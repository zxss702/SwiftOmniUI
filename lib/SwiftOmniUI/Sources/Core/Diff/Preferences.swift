// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// What `.preference` writes onto a node and what `.onPreferenceChange` watches.
// Design: docs/design/core/identity-and-diffing.md#preferences

/// One preference key's workings with its type erased.
struct PreferenceKeyBox {
    /// The key's identity - `ObjectIdentifier(K.self)`.
    let key: ObjectIdentifier

    /// `K.defaultValue`, made fresh each ask.
    let makeDefault: () -> Any

    /// `K.reduce(&value, next)` on `Any` carriers.
    let reduce: (inout Any, () -> Any) -> Void

    /// Whether two answers agree, where the type can say.
    let same: (Any, Any) -> Bool

    /// The box of `K`.
    init<K: PreferenceKey>(_: K.Type) {
        key = ObjectIdentifier(K.self)
        makeDefault = { K.defaultValue }
        reduce = { value, next in
            guard var typed = value as? K.Value, let next = next() as? K.Value else { return }
            K.reduce(value: &typed) { next }
            value = typed
        }
        same = { first, second in
            guard let first = first as? K.Value, let second = second as? K.Value else { return false }
            return PreferenceKeyBox.equal(first, second)
        }
    }

    /// Equality across an existential; a value that cannot say is always different.
    private static func equal(_ a: Any, _ b: Any) -> Bool {
        guard let a = a as? any Equatable else {
            if let a = a as? AnyObject, let b = b as? AnyObject { return a === b }
            return false
        }
        func open<Value: Equatable>(_ a: Value) -> Bool {
            (b as? Value).map { $0 == a } ?? false
        }
        return open(a)
    }
}

/// One `.preference` or `.anchorPreference` write a node carries.
struct PreferenceSeed {
    /// Which key it feeds, and how.
    let box: PreferenceKeyBox

    /// The value this write offers - asked at fold, so a carried element's
    /// offer re-reads what its write stands for: a text's layout answers for
    /// the report the host last handed in, not the one its render saw.
    let value: () -> Any

    /// A seed offering `value` - the same answer every fold, which is every
    /// `.preference` write's.
    init(box: PreferenceKeyBox, value: Any) {
        self.box = box
        self.value = { value }
    }

    /// A seed whose offer is worked out as the fold asks it.
    init(box: PreferenceKeyBox, lazy value: @escaping () -> Any) {
        self.box = box
        self.value = value
    }
}

/// An `.onPreferenceChange` listener a node carries.
struct PreferenceObserver {
    /// Which key it hears, and how to compare.
    let box: PreferenceKeyBox

    /// What runs with the value it had and the one it now has.
    let run: ErasedChangeHandler
}

/// The observer as a rendered element keeps it.
struct PreferenceWatch {
    /// Which key it hears, and how to compare.
    let box: PreferenceKeyBox

    /// The answer it heard last - its default until the first fold lands.
    var last: Any

    /// What runs with the value it had and the one it now has.
    let run: ErasedChangeHandler
}

/// One `.transformPreference` rewrite a node carries.
struct PreferenceTransform {
    /// Which key it rewrites.
    let box: PreferenceKeyBox

    /// The rewrite, on `Any` carriers.
    let apply: (Any) -> Any
}

/// One key's folded answer, kept with the box that folded it.
struct FoldedPreference {
    /// How the value folds and compares.
    let box: PreferenceKeyBox

    /// What the subtree answers.
    var value: Any
}

extension Differ {
    /// What a node's subtree offers for each key: its writes in written order,
    /// each child's folded answers in the children's order, its transforms last.
    func foldedPreferences(
        seeds: [PreferenceSeed],
        transforms: [PreferenceTransform],
        children: [RenderedNode]
    ) -> [ObjectIdentifier: FoldedPreference] {
        var folded: [ObjectIdentifier: FoldedPreference] = [:]

        func offer(_ box: PreferenceKeyBox, _ value: Any) {
            var running = folded[box.key]?.value ?? box.makeDefault()
            box.reduce(&running, { value })
            folded[box.key] = FoldedPreference(box: box, value: running)
        }

        for seed in seeds {
            offer(seed.box, seed.value())
        }

        for child in children {
            for (_, answer) in child.preferenceValues {
                offer(answer.box, answer.value)
            }
        }

        for transform in transforms {
            let answered = folded[transform.box.key]?.value ?? transform.box.makeDefault()
            folded[transform.box.key] = FoldedPreference(
                box: transform.box, value: transform.apply(answered))
        }

        return folded
    }
}
