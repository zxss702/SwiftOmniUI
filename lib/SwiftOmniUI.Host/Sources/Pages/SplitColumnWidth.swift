// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Width bounds keep their axis positions even when a modifier omits the ideal or maximum.
@_spi(Host) public struct SplitColumnWidth: Equatable, Sendable {
    public let minimum: Double
    public let ideal: Double
    public let maximum: Double

    public init(_ values: [Double]?, defaultIdeal: Double = 256) {
        func given(_ index: Int) -> Double? {
            guard let values, values.indices.contains(index), values[index] >= 0,
                  values[index].isFinite else { return nil }
            return values[index]
        }
        minimum = given(0) ?? 0
        maximum = Swift.max(minimum, given(2) ?? (values?.count == 1 ? given(0) : nil) ?? .infinity)
        ideal = Swift.min(maximum, Swift.max(minimum, given(1) ?? given(0) ?? defaultIdeal))
    }

    public func clamp(_ width: Double) -> Double { Swift.min(maximum, Swift.max(minimum, width)) }
}
