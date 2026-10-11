// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

/// The marks the library writes on a node its own pipeline reads before the
/// node mounts - which never reach a host: no element wears the tier, so its
/// members answer for facts alone.
public enum PipelineMarksContract: Contract {
    /// The tier's name.
    public static let name = "PipelineMarks"

    /// Which lazy stack the element is a row of - axis and spacing - so its
    /// unbuilt siblings' room can be stood in for.
    public static let lazyRowStack = ElementProperty<Self, [Double]>(
        "lazyRowStack", layer: .structure, travels: false)

    /// The tier's own members.
    public static let members: [any ContractMember] = [lazyRowStack]
}
