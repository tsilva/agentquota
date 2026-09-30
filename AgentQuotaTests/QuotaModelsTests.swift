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

    func testForecastPredictsExhaustionBeforeReset() {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = start.addingTimeInterval(2 * 3_600)
        let window = makeWindow(
            used: 50,
            duration: 300,
            resetsAt: start.addingTimeInterval(5 * 3_600)
        )

        XCTAssertEqual(
            window.exhaustionForecast(relativeTo: now),
            .runsOut(at: start.addingTimeInterval(4 * 3_600))
        )
    }

    func testForecastDistinguishesBalancedUsageFromUnusedQuota() {
        let start = Date(timeIntervalSince1970: 10_000)
        let reset = start.addingTimeInterval(5 * 3_600)

        XCTAssertEqual(
            makeWindow(used: 50, duration: 300, resetsAt: reset)
                .exhaustionForecast(relativeTo: start.addingTimeInterval(2.5 * 3_600)),
            .lastsUntilReset
        )
        XCTAssertEqual(
            makeWindow(used: 10, duration: 300, resetsAt: reset)
                .exhaustionForecast(relativeTo: start.addingTimeInterval(3_600)),
            .unusedAtReset(percent: 50)
        )
    }

    func testUnusedForecastThresholdAndRounding() {
        let start = Date(timeIntervalSince1970: 10_000)
        let reset = start.addingTimeInterval(5 * 3_600)
        let now = start.addingTimeInterval(3_600)

        XCTAssertEqual(
            makeWindow(used: 19, resetsAt: reset).exhaustionForecast(relativeTo: now),
            .unusedAtReset(percent: 5)
        )
        XCTAssertEqual(
            makeWindow(used: 19, resetsAt: reset)
                .exhaustionForecast(relativeTo: now.addingTimeInterval(-10)),
            .lastsUntilReset
        )
        XCTAssertEqual(
            makeWindow(used: 19, resetsAt: reset)
                .exhaustionForecast(relativeTo: now.addingTimeInterval(30)),
            .unusedAtReset(percent: 6)
        )
    }

    func testMenuWarningPrioritizesRunOutOverTightestWindowAndUnusedQuota() throws {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = start.addingTimeInterval(3_600)
        let unused = makeWindow(id: "unused", used: 10, resetsAt: start.addingTimeInterval(5 * 3_600))
        let balanced = makeWindow(id: "balanced", used: 50, duration: 120, resetsAt: start.addingTimeInterval(2 * 3_600))
        let runsOut = makeWindow(id: "runout", used: 40, resetsAt: start.addingTimeInterval(5 * 3_600))
        let earlier = makeWindow(id: "earlier", used: 45, resetsAt: start.addingTimeInterval(5 * 3_600))
        let snapshot = QuotaSnapshot(planName: "Pro", windows: [unused, balanced, runsOut, earlier], updatedAt: now)

        XCTAssertEqual(snapshot.tightestWindow?.id, "balanced")
        XCTAssertEqual(try XCTUnwrap(snapshot.forecastWarning(relativeTo: now)).window.id, "earlier")
        let exhausted = makeWindow(id: "exhausted", used: 100)
        XCTAssertEqual(
            QuotaSnapshot(planName: "Pro", windows: snapshot.windows + [exhausted], updatedAt: now)
                .forecastWarning(relativeTo: now)?.window.id,
            "exhausted"
        )
    }

    func testMenuWarningSelectsLargestUnusedForecastAndIgnoresUnavailableWindows() {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = start.addingTimeInterval(3_600)
        let reset = start.addingTimeInterval(5 * 3_600)
        let windows = [
            makeWindow(id: "small", used: 15, resetsAt: reset),
            makeWindow(id: "large", used: 10, resetsAt: reset),
            makeWindow(id: "unknown", used: 0, duration: nil, resetsAt: nil)
        ]
        XCTAssertEqual(
            QuotaSnapshot(planName: "Pro", windows: windows, updatedAt: now)
                .forecastWarning(relativeTo: now)?.window.id,
            "large"
        )
        XCTAssertNil(
            QuotaSnapshot(planName: "Pro", windows: [windows[2]], updatedAt: now)
                .forecastWarning(relativeTo: now)
        )
    }

    func testForecastHandlesZeroExhaustedAndClampedUsage() {
        let start = Date(timeIntervalSince1970: 10_000)
        let now = start.addingTimeInterval(3_600)
        let reset = start.addingTimeInterval(5 * 3_600)

        XCTAssertEqual(
            makeWindow(used: 0, duration: 300, resetsAt: reset)
                .exhaustionForecast(relativeTo: now),
            .unusedAtReset(percent: 100)
        )
        XCTAssertEqual(
            makeWindow(used: -20, duration: 300, resetsAt: reset)
                .exhaustionForecast(relativeTo: now),
            .unusedAtReset(percent: 100)
        )
        XCTAssertEqual(
            makeWindow(used: 100, duration: nil, resetsAt: nil)
                .exhaustionForecast(relativeTo: now),
            .exhausted
        )
        XCTAssertEqual(
            makeWindow(used: 140, duration: nil, resetsAt: nil)
                .exhaustionForecast(relativeTo: now),
            .exhausted
        )
    }

    func testForecastIsUnavailableForInvalidWindowTiming() {
        let now = Date(timeIntervalSince1970: 20_000)

        XCTAssertEqual(
            makeWindow(used: 20, duration: nil, resetsAt: now.addingTimeInterval(3_600))
                .exhaustionForecast(relativeTo: now),
            .unavailable
        )
        XCTAssertEqual(
            makeWindow(used: 20, duration: 300, resetsAt: nil)
                .exhaustionForecast(relativeTo: now),
            .unavailable
        )
        XCTAssertEqual(
            makeWindow(used: 20, duration: 0, resetsAt: now.addingTimeInterval(3_600))
                .exhaustionForecast(relativeTo: now),
            .unavailable
        )
        XCTAssertEqual(
            makeWindow(used: 20, duration: 300, resetsAt: now)
                .exhaustionForecast(relativeTo: now),
            .unavailable
        )
        XCTAssertEqual(
            makeWindow(used: 20, duration: 300, resetsAt: now.addingTimeInterval(6 * 3_600))
                .exhaustionForecast(relativeTo: now),
            .unavailable
        )
    }

    func testForecastFormatsCountdownAndLocalRunOutTime() {
        let now = Date(timeIntervalSince1970: 10_000)
        let runOut = now.addingTimeInterval(2 * 3_600 + 15 * 60)
        let forecast = QuotaExhaustionForecast.runsOut(at: runOut)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        XCTAssertEqual(
            forecast.statusDescription(relativeTo: now),
            "At current pace: runs out in 2h 15m"
        )
        XCTAssertEqual(
            forecast.localRunOutDescription(
                calendar: calendar,
                locale: Locale(identifier: "en_GB"),
                timeZone: calendar.timeZone
            ),
            "Thu 1 Jan at 05:01"
        )
        XCTAssertEqual(
            QuotaExhaustionForecast.lastsUntilReset.statusDescription(relativeTo: now),
            "On track until reset"
        )
        XCTAssertEqual(
            QuotaExhaustionForecast.exhausted.statusDescription(relativeTo: now),
            "Quota exhausted"
        )
        XCTAssertEqual(
            QuotaExhaustionForecast.unavailable.statusDescription(relativeTo: now),
            "Run-out prediction unavailable"
        )
        XCTAssertNil(QuotaExhaustionForecast.lastsUntilReset.localRunOutDescription())
        XCTAssertEqual(forecast.title, "Runs out before reset")
        XCTAssertEqual(forecast.detailDescription(relativeTo: now), "At current pace · runs out in 2h 15m")
        XCTAssertEqual(QuotaExhaustionForecast.unusedAtReset(percent: 42).title, "42% likely unused at reset")
        XCTAssertEqual(QuotaExhaustionForecast.unusedAtReset(percent: 42).warningSymbolName, "hourglass")
        XCTAssertEqual(forecast.warningSymbolName, "exclamationmark.triangle")
        XCTAssertNil(QuotaExhaustionForecast.lastsUntilReset.warningSymbolName)
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
