// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A value a view writes for its ancestors to read back: `.preference` writes
/// it, `.onPreferenceChange` and `.backgroundPreferenceValue` hear it, and the
/// key's `reduce` folds what a subtree's views offer into the one value the
/// parent sees.
///
///     struct LayoutKey: PreferenceKey {
///         static var defaultValue: [MarkdownLayout] { [] }
///         static func reduce(value: inout [MarkdownLayout], nextValue: () -> [MarkdownLayout]) {
///             value.append(contentsOf: nextValue())
///         }
///     }
///
/// A leaf writes its part; an ancestor reads all of them:
///
///     .preference(key: LayoutKey.self, value: [layout])
///     .onPreferenceChange(LayoutKey.self) { layouts in … }
public protocol PreferenceKey {
    /// What the key collects.
    associatedtype Value

    /// What a subtree that wrote nothing answers.
    static var defaultValue: Value { get }

    /// Folds the next offered value into the running one; `nextValue` answers
    /// one view's or one child subtree's contribution.
    static func reduce(value: inout Value, nextValue: () -> Value)
}
