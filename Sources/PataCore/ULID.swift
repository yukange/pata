import Foundation

/// Monotonically increasing 128-bit ULID generator and identifier utilities.
/// Matching Crockford's Base32 encoding (lowercase letters + numbers, omitting i, l, o, u).
public struct ULID: Sendable {
    private static let base32Alphabet: [Character] = Array("0123456789abcdefghjkmnpqrstvwxyz")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastTimeMs: UInt64 = 0
    nonisolated(unsafe) private static var lastEntropy: [UInt8] = [UInt8](repeating: 0, count: 10)

    /// Generates a 26-character lowercase ULID string.
    public static func generate() -> String {
        lock.lock()
        defer { lock.unlock() }

        var nowMs = UInt64(Date().timeIntervalSince1970 * 1000)
        if nowMs <= lastTimeMs {
            nowMs = lastTimeMs
            // Increment entropy monotonically
            var carry: UInt16 = 1
            for i in (0..<10).reversed() {
                let sum = UInt16(lastEntropy[i]) + carry
                lastEntropy[i] = UInt8(sum & 0xFF)
                carry = sum >> 8
                if carry == 0 { break }
            }
        } else {
            lastTimeMs = nowMs
            var randomBytes = [UInt8](repeating: 0, count: 10)
            let status = SecRandomCopyBytes(kSecRandomDefault, 10, &randomBytes)
            if status == errSecSuccess {
                lastEntropy = randomBytes
            } else {
                for i in 0..<10 {
                    lastEntropy[i] = UInt8.random(in: 0...255)
                }
            }
        }

        // Encode 48-bit timestamp (6 bytes) + 80-bit entropy (10 bytes) -> 128 bits = 26 Base32 chars
        var bytes = [UInt8](repeating: 0, count: 16)
        bytes[0] = UInt8((nowMs >> 40) & 0xFF)
        bytes[1] = UInt8((nowMs >> 32) & 0xFF)
        bytes[2] = UInt8((nowMs >> 24) & 0xFF)
        bytes[3] = UInt8((nowMs >> 16) & 0xFF)
        bytes[4] = UInt8((nowMs >> 8) & 0xFF)
        bytes[5] = UInt8(nowMs & 0xFF)
        for i in 0..<10 {
            bytes[6 + i] = lastEntropy[i]
        }

        var result = ""
        result.reserveCapacity(26)

        // 128 bits = 26 5-bit groups (with 2 leading zero bits)
        // Group indices:
        let bitLengths: [Int] = [3, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
        var bitOffset = 0
        for len in bitLengths {
            var val: UInt32 = 0
            for b in 0..<len {
                let byteIdx = (bitOffset + b) / 8
                let bitInByte = 7 - ((bitOffset + b) % 8)
                let bitVal = (bytes[byteIdx] >> bitInByte) & 1
                val = (val << 1) | UInt32(bitVal)
            }
            bitOffset += len
            result.append(base32Alphabet[Int(val)])
        }

        return result
    }

    /// Generates an activity ID with prefix "a-", e.g. "a-01j...".
    public static func generateActivityID() -> String {
        return "a-\(generate())"
    }

    /// Generates a stable ID with entity type prefix:
    /// - Task: "t-01j..."
    /// - Note: "n-01j..."
    /// - Activity: "a-01j..."
    /// - DayPlan: "YYYY-MM-DD"
    public static func generateEntityID(type: EntityType) -> String {
        let u = generate()
        switch type {
        case .task:
            return "t-\(u)"
        case .note:
            return "n-\(u)"
        case .activity:
            return "a-\(u)"
        case .dayPlan:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: Date())
        case .file:
            return u
        }
    }

    private static let invalidPathChars = try! NSRegularExpression(pattern: #"[/\\:*?"<>|\x00-\x1f]"#)

    /// Sanitizes human-readable title into a clean filename slug.
    /// Preserves UTF-8 characters (including Chinese), alphanumeric chars, underscores, and hyphens.
    public static func sanitizeSlug(_ title: String) -> String {
        let s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty {
            return "untitled"
        }

        let range = NSRange(location: 0, length: s.utf16.count)
        let cleaned = invalidPathChars.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "-")

        var result = ""
        var lastWasDash = false

        for scalar in cleaned.unicodeScalars {
            if CharacterSet.whitespaces.contains(scalar) || scalar == "-" || scalar == "_" {
                if !lastWasDash && !result.isEmpty {
                    result.append("-")
                    lastWasDash = true
                }
            } else {
                result.append(Character(scalar))
                lastWasDash = false
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
        return trimmed.isEmpty ? "untitled" : trimmed
    }

    /// Standard filename for an entity anchor.
    public static func formatEntityFilename(_ entity: Entity) -> String {
        switch entity.type {
        case .task:
            if let task = entity as? Task {
                let slug = sanitizeSlug(task.title)
                return "\(slug)_\(task.id).md"
            }
            return "\(entity.id).md"
        case .note:
            if let note = entity as? Note {
                if note.draft {
                    return "\(note.id).md"
                }
                let slug = sanitizeSlug(note.title)
                return "\(slug)_\(note.id).md"
            }
            return "\(entity.id).md"
        case .dayPlan:
            if let plan = entity as? DayPlan {
                return "\(plan.date).md"
            }
            return "\(entity.id).md"
        default:
            return "\(entity.id).md"
        }
    }
}
