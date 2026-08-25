import XCTest
@testable import AgentQuota

final class QuotaModelsTests: XCTestCase {
    func testRemainingPercentIsClamped() {
        XCTAssertEqual(makeWindow(used: -25).remainingPercent, 100)
        XCTAssertEqual(makeWindow(used: 41).remainingPercent, 59)
        XCTAssertEqual(makeWindow(used: 140).remainingPercent, 0)
    }

    func testTightestWindowUsesLowestRemainingPercentage() {
        let primary = makeWindow(id: "primary", used: 20)
        let secondary = makeWindow(id: "secondary", used: 75)
        let snapshot = QuotaSnapshot(
            planName: "Pro",
            windows: [primary, secondary],
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(snapshot.tightestWindow?.id, "secondary")
        XCTAssertEqual(snapshot.lowestRemainingPercent, 25)
    }

    func testDurationLabels() {
        XCTAssertEqual(makeWindow(duration: 300).durationLabel, "5-hour")
        XCTAssertEqual(makeWindow(duration: 10_080).durationLabel, "Weekly")
        XCTAssertEqual(makeWindow(duration: 1_440).durationLabel, "Daily")
        XCTAssertEqual(makeWindow(duration: 90).durationLabel, "90-minute")
        XCTAssertEqual(makeWindow(duration: nil).durationLabel, "Quota window")
    }

    func testResetFormattingAndMissingTimestamp() {
        let now = Date(timeIntervalSince1970: 1_000)
        let window = QuotaWindow(
            id: "primary",
            usedPercent: 10,
            durationMinutes: 300,
            resetsAt: now.addingTimeInterval(3 * 3_600 + 12 * 60)
        )

        XCTAssertEqual(window.resetCountdown(relativeTo: now), "Resets in 3h 12m")
        XCTAssertFalse(window.localResetDescription().isEmpty)
        XCTAssertEqual(makeWindow(resetsAt: nil).resetCountdown(relativeTo: now), "Reset time unavailable")
        XCTAssertEqual(makeWindow(resetsAt: nil).localResetDescription(), "Local reset unavailable")
    }

    func testUnknownPlanTypesRemainDisplayable() {
        XCTAssertEqual("pro".quotaPlanDisplayName, "Pro")
        XCTAssertEqual("future_ultra_plan".quotaPlanDisplayName, "Future Ultra Plan")
    }

    private func makeWindow(
        id: String = "window",
        used: Int = 0,
        duration: Int? = 300,
        resetsAt: Date? = Date(timeIntervalSince1970: 10_000)
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            usedPercent: used,
            durationMinutes: duration,
            resetsAt: resetsAt
        )
    }
}
