// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

// `Color` as a view: a colour that stands on its own in the tree.
// Design: docs/design/views/composition.md

extension Color: View {
    /// The colour, filling whatever room it is given - a `Rectangle` painted
    /// with it, stretching to its room.
    public var body: some View {
        Rectangle().fill(self).flex(0)
    }
}
