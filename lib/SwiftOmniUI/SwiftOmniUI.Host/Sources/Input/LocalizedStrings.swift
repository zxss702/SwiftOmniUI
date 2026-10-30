// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore

/// `LocalizedStringKey` resolved on the host: the pattern looked up where the
/// toolkit keeps its tables, then its arguments formatted into the specifiers
/// - the one printf subset `.strings` files carry.
///
/// A host answers `lookup` from its own table - a Bundle's strings on Apple
/// platforms, a provider installed on the toolkit elsewhere - and this turns
/// the answer into the words.
@_spi(Host) public enum HostLocalizedStrings {
    /// What `key` says after the table's say: `lookup` answering a pattern
    /// gets that one formatted, its silence leaves the key's own.
    public static func resolve(
        _ key: LocalizedStringKey,
        lookup: (String) -> String?
    ) -> String {
        format(lookup(key.pattern) ?? key.pattern, arguments: key.arguments)
    }

    /// `pattern` with each `%` specifier replaced by the argument in step
    /// with it: `%@` anything's text, `%lld`/`%d`/`%i` a whole number,
    /// `%f`-family a number, `%.2f` and kin the precision they name, `%%` a
    /// percent sign. An argument short of its specifier leaves the specifier
    /// written; a specifier's shape an argument cannot answer gives the
    /// argument's plain text.
    public static func format(
        _ pattern: String,
        arguments: [LocalizedStringKey.Argument]
    ) -> String {
        var result = ""
        var argument = arguments.startIndex
        var index = pattern.startIndex
        while index < pattern.endIndex {
            guard pattern[index] == "%" else {
                result.append(pattern[index])
                index = pattern.index(after: index)
                continue
            }
            let scanned = specifier(in: pattern, from: index)
            guard let spec = scanned.specifier else {
                // No conversion letter followed the percent: copy it and go on.
                result.append(contentsOf: pattern[index..<scanned.end])
                index = scanned.end
                continue
            }
            if spec.conversion == "%" {
                result.append("%")
                index = scanned.end
                continue
            }
            if argument < arguments.endIndex {
                result.append(format(spec, arguments[argument]))
                argument = arguments.index(after: argument)
            } else {
                result.append(contentsOf: pattern[index..<scanned.end])
            }
            index = scanned.end
        }
        return result
    }

    /// One specifier's flags, width, precision and conversion letter, and
    /// where it ends.
    private struct Specifier {
        var precision: Int?
        var conversion: Character
    }

    /// Letters that qualify a conversion rather than name one - the printf
    /// length markers `%lld` and its kin carry.
    private static let lengthMarkers: Set<Character> = ["l", "h", "z", "t", "q", "L", "j"]

    /// The specifier starting at `percent`, or none where `%` stands alone.
    private static func specifier(
        in pattern: String, from percent: String.Index
    ) -> (specifier: Specifier?, end: String.Index) {
        var spec = Specifier(conversion: "%")
        var index = pattern.index(after: percent)
        var seenPoint = false
        while index < pattern.endIndex {
            let c = pattern[index]
            if c == "%" || (c.isLetter && !lengthMarkers.contains(c)) || c == "@" {
                spec.conversion = c
                return (spec, pattern.index(after: index))
            }
            if c == "." {
                guard !seenPoint else { break }
                seenPoint = true
                index = pattern.index(after: index)
                var digits = 0
                var found = false
                while index < pattern.endIndex, let digit = pattern[index].wholeNumberValue {
                    digits = digits * 10 + digit
                    found = true
                    index = pattern.index(after: index)
                }
                spec.precision = digits
                if !found { spec.precision = 0 }
                continue
            }
            // Flags, width and length markers pass through.
            index = pattern.index(after: index)
        }
        return (nil, index)
    }

    /// One argument through its specifier.
    private static func format(_ spec: Specifier, _ argument: LocalizedStringKey.Argument) -> String {
        switch spec.conversion {
        case "d", "i", "u":
            return argument.wholeText
        case "f", "F", "e", "E", "g", "G":
            return fractionalText(argument, precision: spec.precision, conversion: spec.conversion)
        case "x", "X":
            return argument.hexText(uppercase: spec.conversion == "X")
        case "c", "s", "@":
            return argument.displayText
        default:
            return argument.displayText
        }
    }

    /// The argument's whole-number text: its own where it holds one, the
    /// fraction rounded elsewhere.
    private static func fractionalText(
        _ argument: LocalizedStringKey.Argument,
        precision: Int?,
        conversion: Character
    ) -> String {
        guard let number = argument.value.number else { return argument.displayText }
        switch conversion {
        case "f", "F":
            return fixed(number, fractionDigits: precision ?? 6)
        case "e", "E":
            let text = scientific(number, fractionDigits: precision ?? 6)
            return conversion == "E" ? text.uppercased() : text
        case "g", "G":
            let text = significant(number, digits: precision ?? 6)
            return conversion == "G" ? text.uppercased() : text
        default:
            return fixed(number, fractionDigits: precision ?? 6)
        }
    }

    /// `number` with exactly `digits` after the point, plain notation.
    private static func fixed(_ number: Double, fractionDigits digits: Int) -> String {
        var magnitude = 1.0
        for _ in 0..<digits { magnitude *= 10 }
        let rounded = (number * magnitude).rounded() / magnitude
        var text = String(rounded)
        guard digits > 0 else {
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        if let point = text.firstIndex(of: ".") {
            let have = text.distance(from: text.index(after: point), to: text.endIndex)
            if have > digits {
                text = String(text.prefix(text.distance(from: text.startIndex, to: point) + 1 + digits))
            } else if have < digits {
                text += String(repeating: "0", count: digits - have)
            }
            return text
        }
        return text + "." + String(repeating: "0", count: digits)
    }

    /// `number` in `[-]d.dddde±xx` with `digits` after the point.
    private static func scientific(_ number: Double, fractionDigits digits: Int) -> String {
        guard number != 0 else {
            return "0." + String(repeating: "0", count: digits) + "e+00"
        }
        var exponent = 0
        var mantissa = abs(number)
        while mantissa >= 10 { mantissa /= 10; exponent += 1 }
        while mantissa < 1 { mantissa *= 10; exponent -= 1 }
        let body = fixed(number < 0 ? -mantissa : mantissa, fractionDigits: digits)
        let sign = exponent < 0 ? "-" : "+"
        let magnitude = abs(exponent)
        return body + "e" + sign + (magnitude < 10 ? "0\(magnitude)" : "\(magnitude)")
    }

    /// `number` with about `digits` significant digits, fixed or scientific as
    /// the size calls for - `%g`'s rule.
    private static func significant(_ number: Double, digits: Int) -> String {
        guard number != 0 else { return "0" }
        let magnitude = abs(number)
        let digits = Swift.max(1, digits)
        var limit = 1.0
        for _ in 0..<digits { limit *= 10 }
        if magnitude >= 1e-4, magnitude < limit {
            var exponent = 0
            var probe = magnitude
            while probe >= 10 { probe /= 10; exponent += 1 }
            while probe < 1 { probe *= 10; exponent -= 1 }
            var text = fixed(number, fractionDigits: Swift.max(0, digits - 1 - exponent))
            while text.hasSuffix("0"), text.contains(".") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            return text
        }
        var text = scientific(number, fractionDigits: digits - 1)
        // %g strips the mantissa's trailing zeros.
        if let e = text.firstIndex(of: "e") {
            var mantissa = String(text[text.startIndex..<e])
            while mantissa.hasSuffix("0"), mantissa.contains(".") { mantissa.removeLast() }
            if mantissa.hasSuffix(".") { mantissa.removeLast() }
            text = mantissa + text[e...]
        }
        return text
    }
}

extension LocalizedStringKey.Argument {
    /// The argument as a whole number's text.
    var wholeText: String {
        switch kind {
        case .whole, .number:
            if let number = value.number { return String(Int64(number)) }
            return displayText
        default:
            return displayText
        }
    }

    /// The argument in hex, as `%x` writes it.
    func hexText(uppercase: Bool) -> String {
        guard let number = value.number else { return displayText }
        let text = String(Int64(number), radix: 16)
        return uppercase ? text.uppercased() : text
    }
}
