// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost

/// `PipelineMarksContract` on a host: the marks the library's pipeline reads before a node mounts, which never reach
/// it - no element wears the tier, so the family holds no case of its own.
@_spi(Host) public enum PipelineMarksTests: ConformanceFamily {
    public static let name = "PipelineMarks"

    public static var cases: [ConformanceCase] {
        Specimens.wearing(PipelineMarksContract.self).flatMap { _ in [] }
    }
}
