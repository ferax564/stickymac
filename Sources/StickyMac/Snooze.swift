import Foundation

enum Snooze {
    struct Option { let title: String; let date: Date }

    static func options(now: Date = Date()) -> [Option] {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)!
        let tomorrow9 = cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)!
        let monday9 = cal.nextDate(after: tomorrow9, matching: DateComponents(hour: 9, minute: 0, weekday: 2),
                                   matchingPolicy: .nextTime) ?? tomorrow9.addingTimeInterval(7 * 86400)
        return [
            Option(title: "30 Minutes", date: now.addingTimeInterval(30 * 60)),
            Option(title: "1 Hour", date: now.addingTimeInterval(3600)),
            Option(title: "3 Hours", date: now.addingTimeInterval(3 * 3600)),
            Option(title: "Tomorrow, 9:00", date: tomorrow9),
            Option(title: "Next Monday, 9:00", date: monday9),
        ]
    }

    /// "14:30", "tomorrow 9:00", or "Mon 9:00".
    static func describe(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDate(date, inSameDayAs: now) { return time }
        if let t = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: t) { return "tomorrow " + time }
        return date.formatted(.dateTime.weekday(.abbreviated)) + " " + time
    }
}
