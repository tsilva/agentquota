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
