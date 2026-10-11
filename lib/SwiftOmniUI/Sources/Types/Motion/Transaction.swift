// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A write's animation contract: `withAnimation` sets one for the writes its
// body makes, the render it asks for answers it.
// Design: docs/design/types/animation.md#transactions

#if canImport(WinSDK)
import WinSDK
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#endif

/// The properties of a state write as one change: the animation it runs under,
/// and whether it animates at all.
///
/// `withAnimation` makes one for the writes its body performs. A view reads the
/// transaction its change ran under and animates by it; `.transaction(_:)` on a
/// view rewrites it for the views below.
///
///     withAnimation(.snappy) {
///         expanded.toggle()
///     }
public struct Transaction: Equatable, Sendable {
    /// Native geometry feedback settles layout without starting another size or place journey.
    var isGeometryFeedback = false

    /// The animation the change runs under, or none where the write named none.
    public var animation: Animation?

    /// Whether the change is applied at once however it would have animated.
    public var disablesAnimations: Bool = false

    /// An empty transaction: nothing named.
    public init() {}

    /// A transaction carrying `animation` - SwiftUI's
    /// `Transaction(animation: .snappy)`.
    public init(animation: Animation) {
        self.animation = animation
    }
}

/// The transaction the writes on this thread run under, while a `withAnimation`
/// or `withTransaction` body is on it. This library's own.
enum Transactions {
    /// The transaction per thread, by thread number - writes are allowed from
    /// anywhere, so the running one is whoever called.
    private static let table = Table()

    /// The transaction the calling thread's writes run under, or none.
    static var current: Transaction? {
        let thread = Transactions.thread()
        return table.lock.withLock { table.currents[thread] }
    }

    /// Runs `body` with `transaction` the thread's current, restoring what it
    /// replaced.
    static func run<Result>(_ transaction: Transaction, in body: () throws -> Result) rethrows -> Result {
        let thread = Transactions.thread()

        let previous: Transaction? = table.lock.withLock {
            let previous = table.currents[thread]
            table.currents[thread] = transaction
            return previous
        }

        defer {
            table.lock.withLock { table.currents[thread] = previous }
        }

        return try body()
    }

    /// The lock and the table it guards - a `let` of the pair, so the shared
    /// state is Sendable-safe with the lock doing the guarding.
    private final class Table: @unchecked Sendable {
        let lock = Lock()
        var currents: [UInt64: Transaction] = [:]
    }

    /// Which thread is asking, spelled per platform the way `UIThread.swift` does.
    private static func thread() -> UInt64 {
        #if canImport(WinSDK)
        UInt64(GetCurrentThreadId())
        #else
        UInt64(UInt(bitPattern: pthread_self().hashValue))
        #endif
    }
}

/// Runs `body` with `transaction` the one its writes run under.
///
///     withTransaction(Transaction(animation: .spring())) {
///         shown = false
///     }
///
/// - Parameters:
///   - transaction: what the writes in `body` run under.
///   - body: the work to do.
/// - Returns: what `body` answered.
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    try Transactions.run(transaction, in: body)
}

/// Runs `body` with one part of the transaction rewritten.
public func withTransaction<R, V>(_ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> R) rethrows -> R {
    var transaction = Transactions.current ?? Transaction()
    transaction[keyPath: keyPath] = value
    return try withTransaction(transaction, body)
}

/// Runs `body` so the writes it makes animate under `animation`.
///
///     withAnimation(.snappy) {
///         isShowingDetails = true
///     }
///
/// Every state write in the body animates to its new value under the given
/// animation, whatever animation each view would otherwise answer - except a
/// `.custom` one, which stays with its engine.
///
/// - Parameters:
///   - animation: the animation the changes run under; `nil` for none.
///   - body: the work to do.
/// - Returns: what `body` answered.
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withTransaction(\.animation, animation ?? Animation.none, body)
}
