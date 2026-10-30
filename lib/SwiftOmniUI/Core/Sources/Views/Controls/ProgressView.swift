// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A piece of work's progress - a `ProgressBar` when the fraction is known, an
/// `ActivityIndicator` when it is not:
///
///     ProgressView()                       // work running, length unknown
///     ProgressView("Loading")              // and the words for it
///     ProgressView(done / total)           // 0…1 of the way through
///     ProgressView(value: $done)
///
/// With a binding the bar follows the state and no view is rebuilt for it.
public struct ProgressView: View {
    /// The fraction through the work, 0…1, where it is driven.
    let progress: Binding<Double>?

    /// What it shows where no binding is given; nil for the spinner.
    let value: Double?

    /// The words, or `EmptyView` for the control alone.
    let label: any View

    private init(
        progress: Binding<Double>?, value: Double?,
        @ViewBuilder label: () -> any View
    ) {
        self.progress = progress
        self.value = value
        self.label = label()
    }

    /// Indeterminate - work running whose length is not known.
    public init(@ViewBuilder label: () -> any View) {
        self.init(progress: nil, value: nil, label: label)
    }

    /// Determinate - `value` of `total` done.
    public init(_ value: Double, total: Double, @ViewBuilder label: () -> any View) {
        self.init(progress: nil, value: total > 0 ? value / total : 0, label: label)
    }

    /// Determinate - the value is the fraction itself, 0…1.
    public init(_ value: Double, @ViewBuilder label: () -> any View) {
        self.init(value, total: 1.0, label: label)
    }

    /// Determinate and driven - the binding is the fraction itself, 0…1, and
    /// the host animates the bar to each new value.
    public init(value: Binding<Double>, @ViewBuilder label: () -> any View) {
        self.init(progress: value, value: nil, label: label)
    }

    /// Indeterminate - work running whose length is not known.
    public init() {
        self.init { EmptyView() }
    }

    /// Determinate - `value` of `total` done.
    public init(_ value: Double, total: Double) {
        self.init(value, total: total) { EmptyView() }
    }

    /// Determinate - `value` of `total` done, the SwiftUI spelling.
    ///
    ///     ProgressView(value: downloaded, total: size)
    public init(value: Double, total: Double) {
        self.init(value, total: total) { EmptyView() }
    }

    /// Determinate - the value is the fraction itself, 0…1.
    public init(_ value: Double) {
        self.init(value, total: 1.0) { EmptyView() }
    }

    /// Determinate and driven - the binding is the fraction itself, 0…1.
    public init(value: Binding<Double>) {
        self.init(value: value) { EmptyView() }
    }

    /// Indeterminate, with its words - `ProgressView("Loading")`.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S) {
        self.init { Text(title) }
    }

    /// Indeterminate, with its words looked up.
    public init(_ titleKey: LocalizedStringKey) {
        self.init { Text(titleKey) }
    }

    /// Determinate, with its words.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, value: Double, total: Double) {
        self.init(value, total: total) { Text(title) }
    }

    /// Determinate, with its words looked up.
    public init(_ titleKey: LocalizedStringKey, value: Double, total: Double) {
        self.init(value, total: total) { Text(titleKey) }
    }

    /// Determinate, with its words - the value is the fraction itself, 0…1.
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, value: Double) {
        self.init(value, total: 1.0) { Text(title) }
    }

    /// Determinate, with its words looked up.
    public init(_ titleKey: LocalizedStringKey, value: Double) {
        self.init(value, total: 1.0) { Text(titleKey) }
    }

    /// Determinate and driven, with its words.
    public init(_ title: String, value: Binding<Double>) {
        self.init(value: value) { Text(title) }
    }

    /// The bar or the spinner, under its label where it has one.
    public var body: some View {
        VStack {
            label
            if let progress {
                ProgressBar().progress(progress)
            } else if let value {
                ProgressBar(value)
            } else {
                ActivityIndicator(true)
            }
        }
        .spacing(6)
    }
}

extension View {
    /// How `ProgressView`s inside this view draw - `.circular` for a wheel,
    /// `.linear` for a bar; a control keeping its own wins over the
    /// inherited one:
    ///
    ///     ProgressView()
    ///         .progressViewStyle(.circular)
    ///
    ///     ProgressView(value: done)
    ///         .progressViewStyle(.linear)
    @_disfavoredOverload
    public func progressViewStyle(_ style: some ProgressViewStyle) -> ModifiedContent {
        revised {
            $0.writeInherited(ProgressBarContract.progressStyle, style.progressStyleToken)
            $0.writeInherited(ActivityIndicatorContract.progressStyle, style.progressStyleToken)
        }
    }
}
