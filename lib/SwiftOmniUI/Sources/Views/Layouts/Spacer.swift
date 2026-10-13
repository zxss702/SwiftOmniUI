// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// Room that expands to push a stack's other children apart.
///
///     HStack {
///         Text("Name")
///         Spacer()
///         Button("Edit") {}
///     }
///
/// Draws nothing of its own; the stack hands it a share of what is left over
/// along its axis. With more than one `Spacer` the room is shared evenly.
/// Outside a stack it takes no room.
///
/// Design: docs/design/host/layout.md#stacks
public struct Spacer: View {
    /// The least room it takes along its stack's axis.
    let minLength: Double

    /// Expanding room, any size down to nothing.
    public init() {
        minLength = 0
    }

    /// Expanding room that keeps at least `minLength` along the stack's axis.
    public init(minLength: Double) {
        self.minLength = minLength
    }

    /// An explicitly clear `Rectangle`, marked flexible. Its layout room
    /// must not pick up a shape's default or inherited foreground fill.
    public var body: some View {
        Rectangle().fill(.clear).flex(minLength)
    }
}
