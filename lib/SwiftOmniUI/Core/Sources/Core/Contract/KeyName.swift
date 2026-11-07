// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

import Synchronization

/// A key: the name defining it and the number every comparison and hash works by - the name's own number, the same
/// in every process on every platform. A name is made a key once, where the key is declared, and the work is the
/// number's; keys order by name.
/// Design: docs/design/core/contracts.md#a-key-is-a-number
struct KeyName: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// What defines the key.
    let name: String

    /// What the key is worked by.
    let number: UInt64

    /// The key of `name`. No two names of one number are keys in one process: the second stops it.
    init(_ name: String) {
        var number: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            number ^= UInt64(byte)
            number &*= 0x0000_0100_0000_01b3
        }
        let holder = Self.taken.withLock { names -> String? in
            if let holder = names[number] { return holder == name ? nil : holder }
            names[number] = name
            return nil
        }
        precondition(holder == nil, "the keys `\(name)` and `\(holder ?? "")` share the number \(number)")

        self.name = name
        self.number = number
    }

    /// Whether two keys are one: their numbers are.
    static func == (lhs: KeyName, rhs: KeyName) -> Bool {
        lhs.number == rhs.number
    }

    /// The key's number, hashed.
    func hash(into hasher: inout Hasher) {
        hasher.combine(number)
    }

    /// The order of the names' bytes, so keys sorted read alike in every process, and two keys are ordered
    /// exactly where they are not equal - as their numbers are made from those bytes.
    static func < (lhs: KeyName, rhs: KeyName) -> Bool {
        lhs.name.utf8.lexicographicallyPrecedes(rhs.name.utf8)
    }

    /// The name, so an interpolated diagnostic prints it plainly.
    var description: String { name }

    /// Every number a key of this process holds.
    private static let taken = Mutex<[UInt64: String]>([:])
}
