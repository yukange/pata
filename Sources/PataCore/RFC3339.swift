import Foundation

public struct RFC3339: Sendable {
    nonisolated(unsafe) private static let isoFormatterWithFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let isoFormatterWithoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let standardFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        f.timeZone = TimeZone.current
        return f
    }()

    private static let lock = NSLock()

    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }

        if let d = isoFormatterWithFraction.date(from: trimmed) {
            return d
        }
        if let d = isoFormatterWithoutFraction.date(from: trimmed) {
            return d
        }
        return standardFormatter.date(from: trimmed)
    }

    public static func format(_ date: Date) -> String {
        lock.lock()
        defer { lock.unlock() }
        return standardFormatter.string(from: date)
    }
}
