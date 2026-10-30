// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// An `Equatable` value of any type - what `.animation(_:value:)` compares from
/// render to render. This library's own. `@unchecked Sendable`: the value is
/// written once and only read to compare, on the render thread.
struct AnyEquatableValue: @unchecked Sendable {
    /// The value as it was written.
    private let value: any Equatable

    /// Whether it equals another of the same type.
    private let isEqual: (AnyEquatableValue) -> Bool

    init<V: Equatable>(_ value: V) {
        self.value = value
        isEqual = { other in (other.value as? V) == value }
    }

    static func == (one: AnyEquatableValue, other: AnyEquatableValue) -> Bool {
        one.isEqual(other)
    }
}

/// A `.transaction(_:)`'s rewrite, held so plans can compare: two transforms
/// agree when they are the same box, a rebuilt one never equalling an old.
final class TransactionTransform: @unchecked Sendable {
    let apply: @Sendable (inout Transaction) -> Void

    init(_ apply: @escaping @Sendable (inout Transaction) -> Void) {
        self.apply = apply
    }
}

/// How each of a view's values animates: one answer, and the exceptions to it.
/// Built by `.animation(_:)` and its kin; read by the differ.
/// Design: docs/design/types/animation.md#a-plan-per-view
struct AnimationPlan: Equatable, Sendable {
    /// What every value animates with, where no rule names it.
    var base: Animation?

    /// The exceptions, in writing order; the last one naming a value wins.
    var rules: [(values: AnimationValues, animation: Animation)] = []

    /// The value-gated animations, in writing order - `.animation(_:value:)`:
    /// the last whose value moved wins.
    var gates: [(value: AnyEquatableValue, animation: Animation?)] = []

    /// The `.transaction(_:)` rewrites, in writing order, applied outer first.
    var transactions: [TransactionTransform] = []

    /// How one kind of value animates, or nothing where this plan says. An
    /// armed gate - one whose named value moved this render - answers first;
    /// `armed` names the indexes of those that did, nil outside a diff.
    func animation(for values: AnimationValues, armed: Set<Int> = []) -> Animation? {
        for index in gates.indices.reversed() where armed.contains(index) {
            return gates[index].animation ?? Animation.none
        }

        for rule in rules.reversed() where !rule.values.isDisjoint(with: values) {
            return rule.animation
        }

        return base
    }

    /// The transaction this render runs under, after this plan's rewrites.
    func transaction(under pending: Transaction?) -> Transaction? {
        guard !transactions.isEmpty else { return pending }

        var transaction = pending ?? Transaction()

        for transform in transactions {
            transform.apply(&transaction)
        }

        return transaction
    }

    /// Compares the parts by hand: tuples and transforms are not Equatable.
    static func == (one: AnimationPlan, other: AnimationPlan) -> Bool {
        one.base == other.base
            && one.rules.count == other.rules.count
            && one.gates.count == other.gates.count
            && one.transactions.count == other.transactions.count
            && zip(one.rules, other.rules).allSatisfy {
                $0.values == $1.values && $0.animation == $1.animation
            }
            && zip(one.gates, other.gates).allSatisfy {
                $0.value == $1.value && $0.animation == $1.animation
            }
            && zip(one.transactions, other.transactions).allSatisfy { $0 === $1 }
    }
}

extension AnimationPlan {
    /// A view's own plan with the plan written on it over the top: the written
    /// base wins, and the written rules come later, so they win too.
    static func merged(_ made: AnimationPlan?, under written: AnimationPlan?) -> AnimationPlan? {
        guard let written = written else { return made }
        guard let made = made else { return written }

        return AnimationPlan(
            base: written.base ?? made.base,
            rules: made.rules + written.rules,
            gates: made.gates + written.gates,
            transactions: made.transactions + written.transactions)
    }
}
