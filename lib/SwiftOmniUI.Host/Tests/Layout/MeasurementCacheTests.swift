// SPDX-FileCopyrightText: 2026 Paweł Krzywdziński and Contributors
// SPDX-License-Identifier: Apache-2.0

@_spi(Host) import SwiftOmniUICore
@_spi(Host) import SwiftOmniUIHost
import XCTest

@MainActor final class MeasurementCacheTests: XCTestCase {
    func testCompletedPreparationReusesAnswersAndInvalidatesChangedSpeculation() {
        let cache = MeasurementCache()
        let wide = LayoutSize(width: 200, height: 20)
        let narrow = LayoutSize(width: 50, height: 80)
        _ = cache.size(offering: 200) { wide }
        _ = cache.size(offering: 50) { narrow }
        let revision = cache.revision
        XCTAssertFalse(cache.store(wide, offering: 200))
        XCTAssertEqual(cache.revision, revision)
        XCTAssertEqual(cache.size(offering: 50) { XCTFail("unchanged preparation must retain other proposals"); return .zero }, narrow)
        let changed = LayoutSize(width: 200, height: 40)
        XCTAssertTrue(cache.store(changed, offering: 200))
        XCTAssertGreaterThan(cache.revision, revision)
        XCTAssertEqual(cache.size(offering: 200) { XCTFail("completed result must be kept"); return .zero }, changed)
        var recomputed = false
        _ = cache.size(offering: 50) { recomputed = true; return LayoutSize(width: 50, height: 160) }
        XCTAssertTrue(recomputed)
    }
}
