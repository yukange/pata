import Foundation

/// Note candidate for `[[` note reference completion.
public struct NoteRef: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var path: String

    public init(id: String, title: String, path: String) {
        self.id = id
        self.title = title
        self.path = path
    }
}

/// Backlink source referencing a target Note.
public struct LinkSource: Codable, Sendable, Equatable {
    public var type: EntityType
    public var id: String
    public var title: String
    public var path: String

    public init(type: EntityType, id: String, title: String, path: String) {
        self.type = type
        self.id = id
        self.title = title
        self.path = path
    }
}

public struct Links {
    private static let fencedCodeRe = try! NSRegularExpression(
        pattern: #"(?ms)^[ \t]*(?:```|~~~).*?(?:^[ \t]*(?:```|~~~)[ \t]*$|\z)"#
    )
    private static let inlineCodeRe = try! NSRegularExpression(pattern: #"`[^`\n]*`"#)
    private static let mdLinkRe = try! NSRegularExpression(pattern: #"(!?)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
    private static let urlSchemeRe = try! NSRegularExpression(pattern: #"^[a-zA-Z][a-zA-Z0-9+.-]*:"#)
    private static let textRefRe = try! NSRegularExpression(pattern: #"\\?\[\[([^\[\]\n]+)\]\]"#)

    /// Extracts relative link destinations from Note body, stripping fenced code blocks and inline code.
    public static func noteLinkDests(body: String) -> [String] {
        var clean = body
        let fencedRange = NSRange(location: 0, length: clean.utf16.count)
        clean = fencedCodeRe.stringByReplacingMatches(in: clean, options: [], range: fencedRange, withTemplate: "")
        let inlineRange = NSRange(location: 0, length: clean.utf16.count)
        clean = inlineCodeRe.stringByReplacingMatches(in: clean, options: [], range: inlineRange, withTemplate: "")

        var destinations: [String] = []
        let range = NSRange(location: 0, length: clean.utf16.count)
        let matches = mdLinkRe.matches(in: clean, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let isImg = (clean as NSString).substring(with: match.range(at: 1))
            if isImg == "!" { continue }

            var dest = (clean as NSString).substring(with: match.range(at: 2))
            if dest.hasPrefix("/") || dest.hasPrefix("#") { continue }

            let destRange = NSRange(location: 0, length: dest.utf16.count)
            if urlSchemeRe.firstMatch(in: dest, options: [], range: destRange) != nil {
                continue
            }

            if let idx = dest.firstIndex(where: { $0 == "#" || $0 == "?" }) {
                dest = String(dest[..<idx])
            }

            if let unescaped = dest.removingPercentEncoding {
                dest = unescaped
            }

            if !dest.isEmpty {
                destinations.append(dest)
            }
        }

        return destinations
    }

    /// Extracts `[[title]]` keys from plain text (skips `\[[title]]`).
    public static func textRefKeys(body: String) -> [String] {
        var keys: [String] = []
        let range = NSRange(location: 0, length: body.utf16.count)
        let matches = textRefRe.matches(in: body, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let full = (body as NSString).substring(with: match.range(at: 0))
            if full.hasPrefix("\\") {
                continue
            }
            let key = (body as NSString).substring(with: match.range(at: 1))
            keys.append(key)
        }

        return keys
    }

    /// Resolves `[[title]]` key in the context of given `noteRefs` and all known notes.
    /// Invariant: If bound in `noteRefs`, ONLY returns bound ID if note exists. If target note is missing,
    /// returns nil (NEVER falls back to title matching!).
    /// If unbound, resolves ONLY if exactly 1 note matches title uniquely.
    public static func resolveTextRef(name: String, noteRefs: [String: String], notes: [String: Note]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if let id = noteRefs[name] {
            return notes[id] != nil ? id : nil
        }
        if let id = noteRefs[trimmed] {
            return notes[id] != nil ? id : nil
        }
        for (k, id) in noteRefs {
            if k.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                return notes[id] != nil ? id : nil
            }
        }

        if trimmed.isEmpty {
            return nil
        }

        var foundID: String?
        var count = 0

        for (id, note) in notes {
            if note.title == name || note.title.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed {
                foundID = id
                count += 1
            }
        }

        return count == 1 ? foundID : nil
    }
}
