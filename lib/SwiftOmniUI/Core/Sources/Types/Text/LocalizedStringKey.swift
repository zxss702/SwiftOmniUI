// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// A string that resolves through the host's localization tables - the
/// SwiftUI spelling of "look this text up":
///
///     Text("Save")                      // a literal - a key, looked up
///     Text(name)                        // a String - verbatim, never looked up
///     Text("Elapsed: \(elapsed, specifier: "%.2f") s")
///
/// The key is the literal itself with every interpolation standing as its
/// specifier: `%@` for what is not a whole number, `%lld` for one, or the
/// specifier `\(x, specifier:)` gives - the same keys a `.strings` file or an
/// `.xcstrings` catalog carries.
///
/// The key and its arguments cross to the host, which looks the pattern up in
/// the platform's table - a Bundle's on Apple platforms, an installed
/// provider's elsewhere - and formats the arguments in. A table that names no
/// key falls back to the pattern itself, formatted.
public struct LocalizedStringKey: Sendable, Equatable, HostRepresentable {
    /// The lookup key: the literal with a specifier where each interpolation
    /// stands.
    public var pattern: String

    /// The interpolated values, in written order.
    public var arguments: [Argument]

    /// One interpolated value, as it crosses.
    public struct Argument: Sendable, Equatable {
        /// Which kind the value is, so the host hands `String(format:)`-style
        /// formatting a matching argument.
        public enum Kind: Int32, Sendable {
            /// Text - an `%@` specifier's.
            case string = 0
            /// A whole number - an `%lld`-family specifier's.
            case whole = 1
            /// A number with a fraction - an `%f`-family specifier's.
            case number = 2
            /// True or false.
            case truth = 3
        }

        /// Which kind the value is.
        public let kind: Kind

        /// The value, as a member's value crosses.
        public let value: PropValue

        /// An argument of `kind` holding `value`.
        public init(kind: Kind, value: PropValue) {
            self.kind = kind
            self.value = value
        }

        /// A string argument.
        public static func string(_ value: String) -> Argument {
            Argument(kind: .string, value: .string(value))
        }

        /// A whole-number argument.
        public static func whole(_ value: Int64) -> Argument {
            Argument(kind: .whole, value: .number(Double(value)))
        }

        /// A fractional argument.
        public static func number(_ value: Double) -> Argument {
            Argument(kind: .number, value: .number(value))
        }

        /// A Boolean argument.
        public static func truth(_ value: Bool) -> Argument {
            Argument(kind: .truth, value: .bool(value))
        }

        /// The argument `value` best describes: a whole number stays one so an
        /// `%lld` receives an integer, everything else its own shape.
        static func of(_ value: Any) -> Argument {
            switch value {
            case let value as Bool: return .truth(value)
            case let value as any BinaryInteger: return .whole(Int64(clamping: value))
            case let value as any BinaryFloatingPoint: return .number(Double(value))
            case let value as String: return .string(value)
            default: return .string(String(describing: value))
            }
        }

        /// The argument's plain text - what `displayString` substitutes where
        /// the specifier stands.
        public var displayText: String {
            switch kind {
            case .string: value.string ?? ""
            case .whole: value.number.map { String(Int64($0)) } ?? ""
            case .number: value.number.map { String($0) } ?? ""
            case .truth: value.bool.map { $0 ? "true" : "false" } ?? ""
            }
        }

        /// The argument as a list member crosses it.
        var propValue: PropValue {
            .values([.enumeration(kind.rawValue), value])
        }

        /// The argument back from what crossed, or nil where that is no
        /// argument's shape.
        init?(propValue: PropValue) {
            guard let pair = propValue.values,
                  let kind = pair.value(0)?.enumeration.flatMap(Kind.init(rawValue:)),
                  let value = pair.value(1)
            else { return nil }

            self.init(kind: kind, value: value)
        }
    }

    /// A key of `pattern` and `arguments` - how a deserialized key is made.
    public init(pattern: String, arguments: [Argument] = []) {
        self.pattern = pattern
        self.arguments = arguments
    }

    /// The key as a member's value crosses it: the pattern, then the
    /// arguments, each a kind and its value.
    public var propValue: PropValue {
        .values([.string(pattern), .values(arguments.map(\.propValue))])
    }

    /// The key back from what crossed, or nil where that is no key's shape.
    public init?(propValue: PropValue) {
        guard let parts = propValue.values,
              let pattern = parts.value(0)?.string,
              let rawArguments = parts.value(1)?.values
        else { return nil }

        var arguments: [Argument] = []
        for raw in rawArguments {
            guard let argument = Argument(propValue: raw) else { return nil }
            arguments.append(argument)
        }
        self.init(pattern: pattern, arguments: arguments)
    }

    /// The pattern with its arguments stood in for their specifiers: what the
    /// text says before the host's table has had its say - the fallback a
    /// missing translation would draw, and what reads the element's words in
    /// core see.
    public var displayString: String {
        var result = ""
        var argument = arguments.startIndex
        var index = pattern.startIndex
        while index < pattern.endIndex {
            guard pattern[index] == "%" else {
                result.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }
            let next = pattern.index(after: index)
            if next < pattern.endIndex && pattern[next] == "%" {
                result.append("%")
                index = pattern.index(after: next)
                continue
            }
            // The specifier: flags, width and precision, any length marker,
            // then the conversion character - `%.2f`, `%lld`, `%@`.
            var specifierEnd = next
            while specifierEnd < pattern.endIndex,
                  "-+ #0'0123456789.*".contains(pattern[specifierEnd]) {
                specifierEnd = pattern.index(after: specifierEnd)
            }
            while specifierEnd < pattern.endIndex,
                  "lhztqLj".contains(pattern[specifierEnd]) {
                specifierEnd = pattern.index(after: specifierEnd)
            }
            if specifierEnd < pattern.endIndex {
                specifierEnd = pattern.index(after: specifierEnd)
            }
            if argument < arguments.endIndex {
                result.append(arguments[argument].displayText)
                argument = arguments.index(after: argument)
            } else {
                result.append(contentsOf: pattern[index..<specifierEnd])
            }
            index = specifierEnd
        }
        return result
    }
}

extension LocalizedStringKey: ExpressibleByStringLiteral {
    /// A key of the literal alone.
    public init(stringLiteral value: String) {
        self.init(pattern: value)
    }
}

extension LocalizedStringKey: ExpressibleByStringInterpolation {
    /// The literal's parts and interpolations as they are written.
    public init(stringInterpolation: StringInterpolation) {
        self.init(pattern: stringInterpolation.pattern, arguments: stringInterpolation.arguments)
    }

    /// A key's own interpolation, building the pattern and gathering the
    /// arguments.
    public struct StringInterpolation: StringInterpolationProtocol {
        /// The pattern so far - the literal plus a specifier where each
        /// interpolation stood.
        var pattern = ""

        /// The interpolated values so far.
        var arguments: [Argument] = []

        /// An empty interpolation - `init(stringInterpolation:)` makes one.
        public init(literalCapacity: Int, interpolationCount: Int) {
            pattern.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }

        /// A literal run of the key.
        public mutating func appendLiteral(_ literal: String) {
            pattern.append(literal)
        }

        /// A whole number - an `%lld` in the key.
        public mutating func appendInterpolation(_ value: some BinaryInteger) {
            pattern.append("%lld")
            arguments.append(.of(value))
        }

        /// Anything else - an `%@` in the key: text, a number, a value
        /// described.
        public mutating func appendInterpolation(_ value: Any) {
            pattern.append("%@")
            arguments.append(.of(value))
        }

        /// A value under its own specifier - `\(x, specifier: "%.2f")` puts
        /// `%.2f` in the key.
        public mutating func appendInterpolation<T>(_ value: T, specifier: String) {
            pattern.append(specifier)
            arguments.append(.of(value))
        }
    }
}
