// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `.onChanged`: runs a handler when a value is not what this view carried last
// render. Nothing about it crosses to the host.
// Design: docs/design/core/identity-and-diffing.md#watching-values

/// What `.onChanged` runs, given the old value and the new one, in that order.
///
///     .onChange(of: step) { old, new in
///         direction = new > old ? "forward" : "back"
///     }
///
/// It runs on `@MainActor` like every handler, and may write `@State` and await.
public typealias ChangeHandler<Value> = nonisolated(nonsending) (Value, Value) async throws -> Void

/// The same with the value's type erased - what a node stores.
typealias ErasedChangeHandler = nonisolated(nonsending) (Any, Any) async throws -> Void

/// One value a view watches and what to run when it moves; the comparison is
/// captured where the value's type was known.
struct Watch {
    /// The value as this render wrote it.
    let value: Any

    /// Whether a stored value equals this one, or nil where the types differ - a slot
    /// that changed hands, which starts over rather than firing.
    let matches: (Any) -> Bool?

    /// What to run, given the old value and the new one.
    let run: ErasedChangeHandler

    /// A watch on one value. Written by `.onChanged`, never by hand.
    init<Value: Equatable>(_ value: Value, run: @escaping ErasedChangeHandler) {
        self.value = value
        self.matches = { stored in (stored as? Value).map { $0 == value } }
        self.run = run
    }
}

extension View {
    /// Runs something when `value` is not what it was last render.
    ///
    ///     VStack { … }
    ///         .onChange(of: query) { try await search() }
    ///
    /// The value is compared with the one this view carried last render. It does
    /// not fire when the view first appears - use `.onAppear` for that. The
    /// handler runs once the render has walked the tree, and what it writes before
    /// its first suspension is sent in the same render; a handler that moves the
    /// value it watches every time is a loop.
    ///
    /// Each `.onChange` is paired with its predecessor by the order the modifiers
    /// appear in, so one written under an `if` makes the view start watching afresh.
    ///
    /// - Parameters:
    ///   - value: What to watch. Anything `Equatable`.
    ///   - handler: What to run once the value has moved.
    public func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ handler: @escaping EventHandler
    ) -> ModifiedContent {
        revised {
            $0.watches.append(Watch(value) { _, _ in try await handler() })
            if initial { $0.created.append(handler) }
        }
    }

    /// The same, handed the value it was and the value it now is.
    ///
    ///     Text(status)
    ///         .onChange(of: step) { old, new in
    ///             direction = new > old ? "forward" : "back"
    ///         }
    ///
    /// Which of the two overloads a call means is decided by the closure: one
    /// written `{ … }` takes no arguments and gets the short form, one written
    /// `{ old, new in … }` gets this.
    ///
    /// - Parameters:
    ///   - value: What to watch. Anything `Equatable`.
    ///   - handler: What to run, given the old value and the new one.
    public func onChange<Value: Equatable>(
        of value: Value,
        initial: Bool = false,
        _ handler: @escaping ChangeHandler<Value>
    ) -> ModifiedContent {
        revised {
            $0.watches.append(Watch(value) { old, new in
                // Both casts hold by construction: a slot is written by one modifier.
                guard let old = old as? Value, let new = new as? Value else { return }

                try await handler(old, new)
            })
            if initial { $0.created.append({ try await handler(value, value) }) }
        }
    }
}
