// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// The environment: an object provided above with `.environment()`, resolved
// below by type, and a value written above with `.environment(\.key, _)`,
// resolved by key-path - both through the one `@Environment`.
// Design: docs/design/core/state.md#the-environment

/// One `@Environment` slot, which the differ fills as it walks.
protocol EnvironmentSlot: AnyObject {
    /// The type this slot resolves, as the identity the scope is keyed by. A
    /// keyed slot's is `EnvironmentValues`, which no `.environment()` object
    /// ever answers.
    var wants: ObjectIdentifier { get }

    /// Hands the slot the nearest provided object of its type.
    func fill(_ object: AnyObject)

    /// Hands the slot the keyed values above it - object slots read nothing.
    func fill(values: EnvironmentValues)

    /// What it was handed, or nothing - what `Input.slot` compares.
    var filled: AnyObject? { get }

    /// Whether this slot and a later render's resolved the same: identity for
    /// an object, equality for a value.
    func same(as other: EnvironmentSlot) -> Bool
}

/// An environment slot, resolved one of two ways.
private enum Ask<Value> {
    /// An object of a type, provided by `.environment()` - `Wrapped` where the
    /// property is `Wrapped?`.
    case object(AnyObject.Type)

    /// A value under a key of `EnvironmentValues`, written by
    /// `.environment(\.key, _)`.
    case values(KeyPath<EnvironmentValues, Value>)
}

/// An `Optional`'s parts, for `@Environment(T.self) var t: T?` - the
/// annotation names `T`, the property holds it or nil.
private protocol OptionalParts {
    /// `Wrapped` where it is an object type.
    static var wrappedObject: AnyObject.Type? { get }

    /// `Wrapped` out of an `AnyObject`, or none.
    static func some(_ object: AnyObject) -> Any?

    /// `.none` as the optional type.
    static var none: Any { get }
}

extension Optional: OptionalParts {
    static var wrappedObject: AnyObject.Type? { Wrapped.self as? AnyObject.Type }
    static func some(_ object: AnyObject) -> Any? { object as? Wrapped }
    static var none: Any { Optional<Wrapped>.none as Any }
}

/// An object an ancestor provided with `.environment()`, resolved by its type -
/// or a value an ancestor wrote with `.environment(\.key, _)`, resolved by its
/// key-path.
///
///     struct BasketRow: View {
///         @Environment var basket: Basket
///         @Environment(\.dismiss) private var dismiss
///
///         var content: any View {
///             Text("\(basket.items.count) item(s)")
///         }
///     }
///
/// An object asks by its type - optional, where the view may stand outside what
/// provides it: `@Environment(Cache.self) var cache: Cache?`. A keyed value
/// asks by `EnvironmentValues`, and a view that reads one is rebuilt when what
/// it resolves to moves. A body that reads one of an object's `@State`
/// properties is rebuilt when it changes; the provider, which only passes the
/// reference, is not. Reading a non-optional object no ancestor provided stops
/// the program with its name, except the standard providers and sessions,
/// which every tree has.
@propertyWrapper
public final class Environment<Value>: @unchecked Sendable {
    /// Which environment this slot asks.
    private let ask: Ask<Value>

    /// What the differ resolved for this view's place in the tree - written and read
    /// on the UI thread.
    private var resolved: Value?

    /// Whether `resolved` is an answer rather than not yet - an optional's
    /// `.some(nil)` resolves where `nil` alone would read as unanswered.
    private var answered = false

    /// Declares the slot. The differ fills it before the view's body builds.
    public init() {
        guard let object = Environment.objectValue(of: Value.self) else {
            preconditionFailure("""
                @Environment with no argument asks for an object - \(Value.self) \
                is not one. A value asks by its key: @Environment(\\.key).
                """)
        }
        ask = .object(object)
    }

    /// Declares the slot, the type said out loud - `@Environment(Helper.self)`.
    /// - Parameter type: the type asked for; it only names what the inference
    ///   already says.
    public convenience init(_ type: Value.Type) {
        self.init()
    }

    /// Declares an optional slot, the object's type said out loud -
    /// `@Environment(Cache.self)` for `var cache: Cache?`.
    /// - Parameter type: the object asked for.
    public init<Wrapped: AnyObject>(_ type: Wrapped.Type) where Value == Wrapped? {
        ask = .object(Wrapped.self)
    }

    /// Declares the slot for a keyed environment value - `@Environment(\.dismiss)`.
    /// - Parameter keyPath: the `EnvironmentValues` property to read.
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) {
        ask = .values(keyPath)
    }

    /// The object `Value` or its `Wrapped` names, or nothing where `Value` is
    /// no object at all.
    private static func objectValue(of type: Any.Type) -> AnyObject.Type? {
        (type as? AnyObject.Type) ?? (type as? OptionalParts.Type)?.wrappedObject
    }

    /// The resolved object or keyed value - or, where no walk filled the slot,
    /// the standard provider of the type, which is what lets the application
    /// itself declare one.
    public var wrappedValue: Value {
        if answered, let resolved {
            return resolved
        }

        switch ask {
        case .object(let object):
            if let resolved {
                return resolved
            }

            if let standard = StandardEnvironment.object(for: ObjectIdentifier(object)) as? Value {
                resolved = standard
                return standard
            }

            if let none = (Value.self as? OptionalParts.Type)?.none as? Value {
                return none
            }

            preconditionFailure("""
                @Environment asked for a \(Value.self) and no ancestor \
                provided one. Write .environment(...) with a \(Value.self) \
                on a view above this one.
                """)
        case .values(let keyPath):
            let fresh = resolved ?? EnvironmentValues()[keyPath: keyPath]
            resolved = fresh
            return fresh
        }
    }

    /// The provided object lent on as a `Binding`, so one property of it can
    /// be handed to an input: `TextField($context.note)`. Assigning the WHOLE
    /// binding a new object stops the program - the object is the ancestor's
    /// to provide, and only its properties are writable from below.
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { _ in
                preconditionFailure("""
                    An environment \(Value.self) is provided by an ancestor \
                    and cannot be replaced from below. Write its properties \
                    instead - $context.someProperty lends one on.
                    """)
            })
    }
}

extension Environment: EnvironmentSlot {
    /// The identity the scope is keyed by - the object's type for an object
    /// slot, `EnvironmentValues` for a keyed one, which no provided object
    /// answers.
    var wants: ObjectIdentifier {
        switch ask {
        case .object(let object): ObjectIdentifier(object)
        case .values: ObjectIdentifier(EnvironmentValues.self)
        }
    }

    var filled: AnyObject? { resolved as? AnyObject }

    /// Takes the resolved object; a mismatch leaves the slot for its read to report.
    func fill(_ object: AnyObject) {
        guard case .object = ask else { return }
        if let some = object as? Value {
            resolved = some
            answered = true
        }
    }

    /// Takes the resolved keyed value, reading through the bag to the key's own
    /// default where nothing wrote it.
    func fill(values: EnvironmentValues) {
        guard case .values(let keyPath) = ask else { return }
        resolved = values[keyPath: keyPath]
        answered = true
    }

    /// Objects compare by identity - one ancestor's object is the same ask.
    /// Values compare by `Equatable` where the value offers it, and by
    /// reference where it is one; a value offering neither counts as moved,
    /// which rebuilds but never reads stale.
    func same(as other: EnvironmentSlot) -> Bool {
        switch (ask, (other as? Environment<Value>)?.ask) {
        case (.object, .object):
            return filled === other.filled
        case (.values, .values):
            guard answered, other is Environment<Value>, let other = other as? Environment<Value>, other.answered else {
                return false
            }
            guard let mine = resolved, let theirs = other.resolved else {
                return resolved == nil && other.resolved == nil
            }
            if let equatable = mine as? any Equatable {
                func open<T: Equatable>(_ a: T) -> Bool { (theirs as? T).map { $0 == a } ?? false }
                return open(equatable)
            }
            if let a = mine as? AnyObject, let b = theirs as? AnyObject {
                return a === b
            }
            return false
        default:
            return false
        }
    }
}
