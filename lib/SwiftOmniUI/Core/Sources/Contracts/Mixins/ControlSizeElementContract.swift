// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// How big a control draws - a button, a progress bar, a spinner.
public enum ControlSizeElementContract: Contract {
    /// The tier's name.
    public static let name = "ControlSizeElement"

    /// The size is carried as a value in the tree.
    public static let tiers: [any Contract.Type] = [PropertyContainerContract.self]

    /// The size the control draws at - mini to extra large, the platform's
    /// own where it has one.
    public static let controlSize = ElementProperty<Self, ControlSize>("controlSize", layer: .adaptive)

    /// The tier's own members.
    public static let members: [any ContractMember] = [controlSize]
}
