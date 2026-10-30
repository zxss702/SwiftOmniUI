// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// A closed vocabulary, numbered by SwiftOmniUI: append a case, never insert one.
// Design: docs/design/types/vocabularies.md#written-out-and-appended

/// How a view's drawing composites with what stands under it - what
/// `.blendMode` takes.
///
///     Rectangle().fill(.red)
///         .blendMode(.multiply)
public enum BlendMode: Int32, Sendable {
    /// Drawn plainly over what is under it. The default.
    case normal = 0

    /// Colours multiply - light keeps, dark stains.
    case multiply = 1

    /// The inverse multiply - dark keeps, light lifts.
    case screen = 2

    /// Multiply or screen, by what is under it.
    case overlay = 3

    /// The darker of the two.
    case darken = 4

    /// The lighter of the two.
    case lighten = 5

    /// Brightens the under colour to show the new one.
    case colorDodge = 6

    /// Darkens the under colour to show the new one.
    case colorBurn = 7

    /// A gentler overlay.
    case softLight = 8

    /// A harder overlay.
    case hardLight = 9

    /// The difference of the two.
    case difference = 10

    /// The difference that keeps white white.
    case exclusion = 11

    /// The new colour's hue on the under one's light.
    case hue = 12

    /// The new colour's saturation on the under one's.
    case saturation = 13

    /// The new colour's hue and saturation, the under one's light.
    case color = 14

    /// The new colour's light, the under one's hue and saturation.
    case luminosity = 15

    /// The new colour where it is over the old, the old on top.
    case sourceAtop = 16

    /// The new colour under the old.
    case destinationOver = 17

    /// The old colour where the new is not.
    case destinationOut = 18

    /// Adds the two, dark colours deeper.
    case plusDarker = 19

    /// Adds the two, light colours lighter.
    case plusLighter = 20
}

extension BlendMode: HostRepresentable {}
extension BlendMode: StateChoice {}
