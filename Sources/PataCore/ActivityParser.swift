import Foundation
import Yams

public struct ActivityParser {
    public static let activityStartTag = "<!-- pata:activity"
    public static let activityEndMeta  = "-->"
    public static let activityEndTag   = "<!-- /pata:activity -->"

    public static func isActivityMarkerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\\t "))
        return trimmed == activityStartTag || trimmed == activityEndTag
    }

    /// Parses embedded activity blocks from markdown body.
    public static func parseActivities(_ raw: String) throws -> [Activity] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let trimmedAll = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAll.isEmpty {
            return []
        }

        let lines = normalized.components(separatedBy: "\n")
        enum State {
            case outside
            case meta
            case body
        }

        var state = State.outside
        var metaLines: [String] = []
        var bodyLines: [String] = []
        var activities: [Activity] = []
        var seenIDs: Set<String> = []

        for (lineIdx, line) in lines.enumerated() {
            let lineNum = lineIdx + 1
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            switch state {
            case .outside:
                if trimmed.isEmpty {
                    continue
                }
                if trimmed == activityStartTag {
                    state = .meta
                    metaLines = []
                    bodyLines = []
                } else {
                    throw SchemaError.parseError("unexpected content outside activity block at line \(lineNum): '\(trimmed)'")
                }

            case .meta:
                if trimmed == activityEndMeta {
                    state = .body
                } else if trimmed == activityStartTag {
                    throw SchemaError.parseError("nested activity start tag at line \(lineNum)")
                } else if trimmed == activityEndTag {
                    throw SchemaError.parseError("unexpected activity end tag in metadata at line \(lineNum)")
                } else {
                    metaLines.append(line)
                }

            case .body:
                if trimmed == activityEndTag {
                    let metaYaml = metaLines.joined(separator: "\n")
                    guard let loaded = try Yams.load(yaml: metaYaml) as? [String: Any] else {
                        throw SchemaError.parseError("invalid YAML in activity metadata")
                    }

                    guard let rawID = loaded["id"] as? String else {
                        throw SchemaError.validationError(field: "activities.id", reason: "activity missing required 'id'")
                    }
                    let id = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard id.hasPrefix("a-"), id.count > 2 else {
                        throw SchemaError.validationError(field: "activities.id", reason: "activity id must start with 'a-'; got '\(id)'")
                    }

                    var date: Date?
                    if let atStr = loaded["at"] as? String {
                        date = RFC3339.parse(atStr)
                    } else if let atDate = loaded["at"] as? Date {
                        date = atDate
                    }
                    guard let at = date else {
                        throw SchemaError.validationError(field: "activities.at", reason: "activity \(id) missing required valid timestamp 'at'")
                    }

                    var by: String?
                    if let rawBy = loaded["by"] as? String {
                        let trimmedBy = rawBy.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedBy.isEmpty {
                            guard trimmedBy == SourceAgent else {
                                throw SchemaError.validationError(field: "activities.by", reason: "must be 'agent' or omitted; got '\(trimmedBy)'")
                            }
                            by = trimmedBy
                        }
                    }

                    var tags: [String] = []
                    if let rawTags = loaded["tags"] as? [Any] {
                        for (idx, t) in rawTags.enumerated() {
                            let tagStr = String(describing: t)
                            if tagStr.contains("#") {
                                throw SchemaError.validationError(field: "activities.tags[\(idx)]", reason: "activity \(id) tag must not contain '#': '\(tagStr)'")
                            }
                            tags.append(tagStr)
                        }
                    }

                    var noteRefs: [String: String] = [:]
                    if let rawRefs = loaded["note_refs"] as? [String: Any] {
                        for (k, v) in rawRefs {
                            noteRefs[k] = String(describing: v)
                        }
                    }

                    if seenIDs.contains(id) {
                        throw SchemaError.validationError(field: "activities.id", reason: "duplicate activity id '\(id)' in same entity")
                    }
                    seenIDs.insert(id)

                    // Unescape body lines
                    var unescapedBody: [String] = []
                    for bl in bodyLines {
                        if bl.hasPrefix("\\") && isActivityMarkerLine(String(bl.dropFirst())) {
                            unescapedBody.append(String(bl.dropFirst()))
                        } else {
                            unescapedBody.append(bl)
                        }
                    }

                    var extra: [String: String] = [:]
                    for (k, v) in loaded {
                        if k != "id" && k != "at" && k != "by" && k != "tags" && k != "note_refs" {
                            extra[k] = String(describing: v)
                        }
                    }

                    activities.append(Activity(
                        id: id,
                        at: at,
                        by: by,
                        tags: tags,
                        noteRefs: noteRefs,
                        body: unescapedBody.joined(separator: "\n"),
                        extra: extra
                    ))

                    state = .outside
                } else if trimmed == activityStartTag {
                    throw SchemaError.parseError("nested activity start tag without closing previous activity at line \(lineNum)")
                } else {
                    bodyLines.append(line)
                }
            }
        }

        if state != .outside {
            throw SchemaError.parseError("unclosed activity block: missing \(activityEndTag)")
        }

        return activities
    }

    /// Formats activities into embedded HTML comment blocks.
    public static func formatActivities(_ activities: [Activity]) throws -> String {
        if activities.isEmpty {
            return ""
        }

        var blocks: [String] = []
        for act in activities {
            var metaDict: [String: Any] = [
                "id": act.id,
                "at": RFC3339.format(act.at)
            ]
            if let by = act.by, !by.isEmpty {
                metaDict["by"] = by
            }
            if !act.tags.isEmpty {
                metaDict["tags"] = act.tags
            }
            if !act.noteRefs.isEmpty {
                metaDict["note_refs"] = act.noteRefs
            }
            for (k, v) in act.extra {
                metaDict[k] = v
            }

            let metaYaml = try Yams.dump(object: metaDict, width: -1)
            let trimmedYaml = metaYaml.trimmingCharacters(in: .whitespacesAndNewlines)

            var block = "\(activityStartTag)\n\(trimmedYaml)\n\(activityEndMeta)\n"

            if !act.body.isEmpty {
                let normalized = act.body.replacingOccurrences(of: "\r\n", with: "\n")
                let lines = normalized.components(separatedBy: "\n")
                for line in lines {
                    if isActivityMarkerLine(line) {
                        block.append("\\\(line)\n")
                    } else {
                        block.append("\(line)\n")
                    }
                }
            }

            block.append(activityEndTag)
            blocks.append(block)
        }

        return blocks.joined(separator: "\n\n") + "\n"
    }
}
