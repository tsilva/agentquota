import Foundation

struct QuotaSnapshot: Equatable, Sendable {
    let planName: String
    let windows: [QuotaWindow]
    let updatedAt: Date

    var tightestWindow: QuotaWindow? {
        windows.min { lhs, rhs in
            lhs.remainingPercent < rhs.remainingPercent
        }
    }

    var lowestRemainingPercent: Int? {
        tightestWindow?.remainingPercent
    }

    func forecastWarning(relativeTo now: Date) -> (window: QuotaWindow, forecast: QuotaExhaustionForecast)? {
        windows.compactMap { window in
            let forecast = window.exhaustionForecast(relativeTo: now)
            return forecast.warningSymbolName == nil ? nil : (window: window, forecast: forecast)
        }.max { lhs, rhs in
            if lhs.forecast.warningPriority != rhs.forecast.warningPriority {
                return lhs.forecast.warningPriority < rhs.forecast.warningPriority
            }
            switch (lhs.forecast, rhs.forecast) {
            case let (.runsOut(left), .runsOut(right)):
                return left > right
            case let (.unusedAtReset(left), .unusedAtReset(right)):
                return left < right
            default:
                return false
            }
        }
    }
}

enum QuotaExhaustionForecast: Equatable, Sendable {
    case runsOut(at: Date)
    case unusedAtReset(percent: Int)
    case lastsUntilReset
    case exhausted
    case unavailable

    var title: String {
        switch self {
        case .runsOut:
            return "Runs out before reset"
        case let .unusedAtReset(percent):
            return "\(percent)% likely unused at reset"
        case .lastsUntilReset:
            return "On track until reset"
        case .exhausted:
            return "Quota exhausted"
        case .unavailable:
            return "Forecast unavailable"
        }
    }

    var warningSymbolName: String? {
        switch self {
        case .runsOut, .exhausted:
            return "exclamationmark.triangle"
        case .unusedAtReset:
            return "hourglass"
        case .lastsUntilReset, .unavailable:
            return nil
        }
    }

    fileprivate var warningPriority: Int {
        switch self {
        case .exhausted: return 3
        case .runsOut: return 2
        case .unusedAtReset: return 1
        case .lastsUntilReset, .unavailable: return 0
        }
    }

    func detailDescription(relativeTo now: Date) -> String {
        switch self {
        case .runsOut:
            return statusDescription(relativeTo: now).replacingOccurrences(of: ": ", with: " · ")
        case .unusedAtReset, .lastsUntilReset:
            return "Forecast at your current pace"
        case .exhausted:
            return "Available again at the next reset"
        case .unavailable:
            return "Waiting for an active quota window"
        }
    }

    func statusDescription(relativeTo now: Date) -> String {
        switch self {
        case let .runsOut(at):
            let seconds = Int(at.timeIntervalSince(now))
            guard seconds > 0 else {
                return "At current pace: runs out now"
            }
            return "At current pace: runs out \(Self.countdown(seconds: seconds))"
        case .unusedAtReset, .lastsUntilReset:
            return title
        case .exhausted:
            return "Quota exhausted"
        case .unavailable:
            return "Run-out prediction unavailable"
        }
    }

    func localRunOutDescription(
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String? {
        guard case let .runsOut(at) = self else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d, HH:mm")
        return formatter.string(from: at)
    }

    private static func countdown(seconds: Int) -> String {
        if seconds < 60 {
            return "in <1m"
        }

        let totalMinutes = seconds / 60
        if totalMinutes < 60 {
            return "in \(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            return minutes == 0
                ? "in \(totalHours)h"
                : "in \(totalHours)h \(minutes)m"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        return hours == 0
            ? "in \(days)d"
            : "in \(days)d \(hours)h"
    }
}

struct QuotaWindow: Equatable, Identifiable, Sendable {
    let id: String
    let usedPercent: Int
    let remainingPercent: Int
    let durationMinutes: Int?
    let resetsAt: Date?

    init(
        id: String,
        usedPercent: Int,
        durationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.id = id
        self.usedPercent = usedPercent
        remainingPercent = min(max(100 - usedPercent, 0), 100)
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }

    var durationLabel: String {
        guard let durationMinutes, durationMinutes > 0 else {
            return "Quota window"
        }

        switch durationMinutes {
        case 60:
            return "Hourly"
        case 1_440:
            return "Daily"
        case 10_080:
            return "Weekly"
        default:
            if durationMinutes.isMultiple(of: 10_080) {
                return "\(durationMinutes / 10_080)-week"
            }
            if durationMinutes.isMultiple(of: 1_440) {
                return "\(durationMinutes / 1_440)-day"
            }
            if durationMinutes.isMultiple(of: 60) {
                return "\(durationMinutes / 60)-hour"
            }
            return "\(durationMinutes)-minute"
        }
    }

    func exhaustionForecast(relativeTo now: Date) -> QuotaExhaustionForecast {
        let consumedPercent = min(max(usedPercent, 0), 100)
        if consumedPercent == 100 {
            return .exhausted
        }

        guard
            let durationMinutes,
            durationMinutes > 0,
            let resetsAt,
            resetsAt > now
        else {
            return .unavailable
        }

        let duration = TimeInterval(durationMinutes) * 60
        guard duration.isFinite, duration > 0 else {
            return .unavailable
        }

        let windowStart = resetsAt.addingTimeInterval(-duration)
        let elapsed = now.timeIntervalSince(windowStart)
        guard elapsed > 0, elapsed < duration else {
            return .unavailable
        }

        guard consumedPercent > 0 else {
            return .unusedAtReset(percent: 100)
        }

        let secondsUntilExhaustion = elapsed
            * Double(100 - consumedPercent)
            / Double(consumedPercent)
        guard secondsUntilExhaustion.isFinite, secondsUntilExhaustion >= 0 else {
            return .unavailable
        }

        let predictedExhaustion = now.addingTimeInterval(secondsUntilExhaustion)
        if predictedExhaustion < resetsAt {
            return .runsOut(at: predictedExhaustion)
        }

        let projectedUnused = max(100 - Double(consumedPercent) * duration / elapsed, 0)
        // Ignore small leftovers so near-balanced usage has a quiet on-track state.
        return projectedUnused >= 5
            ? .unusedAtReset(percent: Int(projectedUnused.rounded()))
            : .lastsUntilReset
    }

    func resetCountdown(relativeTo now: Date) -> String {
        guard let resetsAt else {
            return "Reset time unavailable"
        }

        let seconds = Int(resetsAt.timeIntervalSince(now))
        guard seconds > 0 else {
            return "Resetting now"
        }

        if seconds < 60 {
            return "Resets in <1m"
        }

        let totalMinutes = seconds / 60
        if totalMinutes < 60 {
            return "Resets in \(totalMinutes)m"
        }

        let totalHours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if totalHours < 24 {
            return minutes == 0
                ? "Resets in \(totalHours)h"
                : "Resets in \(totalHours)h \(minutes)m"
        }

        let days = totalHours / 24
        let hours = totalHours % 24
        return hours == 0
            ? "Resets in \(days)d"
            : "Resets in \(days)d \(hours)h"
    }

    func localResetDescription(calendar: Calendar = .autoupdatingCurrent) -> String {
        guard let resetsAt else {
            return "Local reset unavailable"
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.calendar = calendar
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d, HH:mm")
        return formatter.string(from: resetsAt)
    }
}

extension String {
    var quotaPlanDisplayName: String {
        let knownNames = [
            "free": "Free",
            "go": "Go",
            "plus": "Plus",
            "pro": "Pro",
            "prolite": "Pro Lite",
            "team": "Team",
            "business": "Business",
            "enterprise": "Enterprise",
            "edu": "Education",
            "ent26": "Enterprise",
            "self_serve_business_prolite": "Business Pro Lite",
            "self_serve_business_usage_based": "Business Usage Based",
            "enterprise_cbp_automation": "Enterprise Automation",
            "enterprise_cbp_usage_based": "Enterprise Usage Based"
        ]

        if let knownName = knownNames[lowercased()] {
            return knownName
        }

        return replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
