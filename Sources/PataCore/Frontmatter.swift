import Foundation
import Yams

public struct Frontmatter {
    /// Splits raw markdown content into YAML frontmatter string and body string.
    public static func splitFrontmatter(_ content: String) throws -> (yaml: String?, body: String, hasFrontmatter: Bool) {
        var str = content
        // Strip UTF-8 BOM if present
        if str.hasPrefix("\u{feff}") {
            str = String(str.dropFirst())
        }

        let trimmedLeading = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedLeading.hasPrefix("---") {
            return (nil, str, false)
        }

        let lines = str.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let firstLine = lines.first, firstLine.trimmingCharacters(in: .whitespaces) == "---" else {
            return (nil, str, false)
        }

        var yamlLines: [String] = []
        var closingFound = false
        var bodyStartIdx = 0

        for i in 1..<lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                closingFound = true
                bodyStartIdx = i + 1
                break
            }
            yamlLines.append(line)
        }

        if !closingFound {
            throw SchemaError.parseError("unclosed frontmatter: missing closing '---'")
        }

        let yamlStr = yamlLines.joined(separator: "\n")
        var bodyStr = ""
        if bodyStartIdx < lines.count {
            bodyStr = lines[bodyStartIdx...].joined(separator: "\n")
            if bodyStr.hasPrefix("\n") {
                bodyStr = String(bodyStr.dropFirst())
            }
        }

        return (yamlStr, bodyStr, true)
    }

    private static func derivePlainMarkdownTitle(body: String, filePath: String) -> String {
        let lines = body.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let t = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !t.isEmpty {
                    return String(t)
                }
            }
        }
        if !filePath.isEmpty {
            let url = URL(fileURLWithPath: filePath)
            return url.deletingPathExtension().lastPathComponent
        }
        return "untitled"
    }

    /// Parses markdown text into a strongly typed Entity.
    public static func parseMarkdown(filePath: String = "", content: String) throws -> any Entity {
        let (yamlOpt, body, hasFM) = try splitFrontmatter(content)

        if !hasFM || yamlOpt == nil {
            let hash = Safety.computeContentHash(Data(filePath.utf8))
            let prefix = hash.prefix(16)
            let placeholderID = "plain-\(prefix)"
            let title = derivePlainMarkdownTitle(body: body, filePath: filePath)
            let now = Date()
            return Note(
                id: placeholderID,
                draft: false,
                title: title,
                tags: [],
                createdAt: now,
                updatedAt: now,
                body: content
            )
        }

        let yamlStr = yamlOpt!
        guard let rawDict = try Yams.load(yaml: yamlStr) as? [String: Any] else {
            throw SchemaError.parseError("invalid YAML in frontmatter", path: filePath)
        }

        guard let rawType = rawDict["type"] as? String, !rawType.isEmpty else {
            throw SchemaError.parseError("missing required 'type' field in frontmatter", path: filePath)
        }

        guard let entityType = EntityType(rawValue: rawType) else {
            throw SchemaError.parseError("unsupported entity type '\(rawType)'", path: filePath)
        }

        let entity: any Entity

        switch entityType {
        case .task:
            var task = try parseTask(rawDict, body: body, filePath: filePath)
            // Gracefully normalize legacy doing status
            if task.status == .doing {
                task.status = .todo
            }
            // If task is done but completed_at is not set, infer from latest completed event or updatedAt
            if task.status == .done && task.completedAt == nil {
                for ev in task.statusEvents.reversed() {
                    if ev.action == .completed {
                        task.completedAt = ev.at
                        break
                    }
                }
                if task.completedAt == nil {
                    task.completedAt = task.updatedAt
                }
            }
            entity = task

        case .note:
            entity = try parseNote(rawDict, body: body, filePath: filePath)

        case .dayPlan:
            entity = try parseDayPlan(rawDict, body: body, filePath: filePath)

        default:
            throw SchemaError.parseError("unsupported entity type '\(rawType)'", path: filePath)
        }

        try SchemaValidator.validateEntity(entity, path: filePath)
        return entity
    }

    private static func parseTask(_ dict: [String: Any], body: String, filePath: String) throws -> Task {
        let id = (dict["id"] as? String) ?? ""
        let title = (dict["title"] as? String) ?? ""
        let description = (dict["description"] as? String) ?? ""
        let statusStr = (dict["status"] as? String) ?? "todo"
        let status = TaskStatus(rawValue: statusStr) ?? .todo

        var completedAt: Date?
        if let caStr = dict["completed_at"] as? String {
            completedAt = RFC3339.parse(caStr)
        } else if let caDate = dict["completed_at"] as? Date {
            completedAt = caDate
        }

        let due = dict["due"] as? String

        var tags: [String] = []
        if let rawTags = dict["tags"] as? [Any] {
            tags = rawTags.map { String(describing: $0) }
        }

        var noteIds: [String] = []
        if let rawNoteIds = dict["note_ids"] as? [Any] {
            noteIds = rawNoteIds.map { String(describing: $0) }
        }

        var noteRefs: [String: String] = [:]
        if let rawNoteRefs = dict["note_refs"] as? [String: Any] {
            for (k, v) in rawNoteRefs {
                noteRefs[k] = String(describing: v)
            }
        }

        var createdAt = Date()
        if let caStr = dict["created_at"] as? String, let d = RFC3339.parse(caStr) {
            createdAt = d
        } else if let caDate = dict["created_at"] as? Date {
            createdAt = caDate
        }

        let createdBy = dict["created_by"] as? String

        var updatedAt = Date()
        if let uaStr = dict["updated_at"] as? String, let d = RFC3339.parse(uaStr) {
            updatedAt = d
        } else if let uaDate = dict["updated_at"] as? Date {
            updatedAt = uaDate
        }

        var statusEvents: [StatusEvent] = []
        if let rawEvents = dict["status_events"] as? [[String: Any]] {
            for evDict in rawEvents {
                let actionStr = (evDict["action"] as? String) ?? ""
                guard let action = StatusEventAction(rawValue: actionStr) else { continue }
                var evDate: Date?
                if let atStr = evDict["at"] as? String {
                    evDate = RFC3339.parse(atStr)
                } else if let atDate = evDict["at"] as? Date {
                    evDate = atDate
                }
                guard let at = evDate else { continue }
                let by = evDict["by"] as? String
                statusEvents.append(StatusEvent(action: action, at: at, by: by))
            }
        }

        var extra: [String: String] = [:]
        let knownKeys: Set<String> = [
            "type", "id", "title", "description", "status", "completed_at", "due",
            "tags", "note_ids", "note_refs", "created_at", "created_by", "updated_at", "status_events"
        ]
        for (k, v) in dict {
            if !knownKeys.contains(k) {
                extra[k] = String(describing: v)
            }
        }

        var finalDesc = description
        var activities: [Activity] = []

        if body.contains(ActivityParser.activityStartTag) {
            activities = try ActivityParser.parseActivities(body)
        } else if description.isEmpty && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Legacy task with description in body
            finalDesc = body.trimmingCharacters(in: .whitespacesAndNewlines)
            activities = []
        } else {
            activities = try ActivityParser.parseActivities(body)
        }

        return Task(
            id: id,
            title: title,
            description: finalDesc,
            status: status,
            completedAt: completedAt,
            due: due,
            tags: tags,
            noteIds: noteIds,
            noteRefs: noteRefs,
            createdAt: createdAt,
            createdBy: createdBy,
            updatedAt: updatedAt,
            statusEvents: statusEvents,
            extra: extra,
            body: body,
            activities: activities
        )
    }

    private static func parseNote(_ dict: [String: Any], body: String, filePath: String) throws -> Note {
        let id = (dict["id"] as? String) ?? ""
        let draft = (dict["draft"] as? Bool) ?? false
        let title = (dict["title"] as? String) ?? ""

        var tags: [String] = []
        if let rawTags = dict["tags"] as? [Any] {
            tags = rawTags.map { String(describing: $0) }
        }

        let audioFile = dict["audio_file"] as? String
        let audioTranscript = (dict["audio_transcript"] as? Bool) ?? false

        var createdAt = Date()
        if let caStr = dict["created_at"] as? String, let d = RFC3339.parse(caStr) {
            createdAt = d
        } else if let caDate = dict["created_at"] as? Date {
            createdAt = caDate
        }

        let createdBy = dict["created_by"] as? String

        var updatedAt = Date()
        if let uaStr = dict["updated_at"] as? String, let d = RFC3339.parse(uaStr) {
            updatedAt = d
        } else if let uaDate = dict["updated_at"] as? Date {
            updatedAt = uaDate
        }

        var extra: [String: String] = [:]
        let knownKeys: Set<String> = [
            "type", "id", "draft", "title", "tags", "audio_file", "audio_transcript",
            "created_at", "created_by", "updated_at"
        ]
        for (k, v) in dict {
            if !knownKeys.contains(k) {
                extra[k] = String(describing: v)
            }
        }

        return Note(
            id: id,
            draft: draft,
            title: title,
            tags: tags,
            audioFile: audioFile,
            audioTranscript: audioTranscript,
            createdAt: createdAt,
            createdBy: createdBy,
            updatedAt: updatedAt,
            extra: extra,
            body: body
        )
    }

    private static func parseDayPlan(_ dict: [String: Any], body: String, filePath: String) throws -> DayPlan {
        var date = (dict["date"] as? String) ?? ""
        if date.isEmpty, let d = dict["date"] as? Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(secondsFromGMT: 0)
            date = f.string(from: d)
        }

        var taskIds: [String] = []
        if let rawTaskIds = dict["task_ids"] as? [Any] {
            taskIds = rawTaskIds.map { String(describing: $0) }
        }

        var extra: [String: String] = [:]
        let knownKeys: Set<String> = ["type", "date", "task_ids"]
        for (k, v) in dict {
            if !knownKeys.contains(k) {
                extra[k] = String(describing: v)
            }
        }

        let activities = try ActivityParser.parseActivities(body)

        return DayPlan(
            date: date,
            taskIds: taskIds,
            extra: extra,
            body: body,
            activities: activities
        )
    }

    /// Serializes an Entity into frontmatter + markdown body bytes.
    public static func serializeMarkdown(_ entity: any Entity) throws -> String {
        var dict: [String: Any] = [
            "type": entity.type.rawValue
        ]

        var finalBody = entity.body

        switch entity.type {
        case .task:
            guard let t = entity as? Task else { break }
            dict["id"] = t.id
            dict["title"] = t.title
            if !t.description.isEmpty {
                dict["description"] = t.description
            }
            dict["status"] = t.status.rawValue
            if let completedAt = t.completedAt {
                dict["completed_at"] = RFC3339.format(completedAt)
            } else {
                dict["completed_at"] = nil as String?
            }
            if let due = t.due {
                dict["due"] = due
            } else {
                dict["due"] = nil as String?
            }
            if !t.tags.isEmpty {
                dict["tags"] = t.tags
            }
            if !t.noteIds.isEmpty {
                dict["note_ids"] = t.noteIds
            }
            if !t.noteRefs.isEmpty {
                dict["note_refs"] = t.noteRefs
            }
            dict["created_at"] = RFC3339.format(t.createdAt)
            if let cb = t.createdBy, !cb.isEmpty {
                dict["created_by"] = cb
            }
            dict["updated_at"] = RFC3339.format(t.updatedAt)

            if !t.statusEvents.isEmpty {
                var eventsList: [[String: Any]] = []
                for ev in t.statusEvents {
                    var evDict: [String: Any] = [
                        "action": ev.action.rawValue,
                        "at": RFC3339.format(ev.at)
                    ]
                    if let by = ev.by, !by.isEmpty {
                        evDict["by"] = by
                    }
                    eventsList.append(evDict)
                }
                dict["status_events"] = eventsList
            }

            finalBody = try ActivityParser.formatActivities(t.activities)

        case .note:
            guard let n = entity as? Note else { break }
            dict["id"] = n.id
            if n.draft {
                dict["draft"] = true
            }
            if !n.title.isEmpty || !n.draft {
                dict["title"] = n.title
            }
            if !n.tags.isEmpty {
                dict["tags"] = n.tags
            }
            if let af = n.audioFile, !af.isEmpty {
                dict["audio_file"] = af
            }
            if n.audioTranscript {
                dict["audio_transcript"] = true
            }
            dict["created_at"] = RFC3339.format(n.createdAt)
            if let cb = n.createdBy, !cb.isEmpty {
                dict["created_by"] = cb
            }
            dict["updated_at"] = RFC3339.format(n.updatedAt)

            finalBody = n.body

        case .dayPlan:
            guard let p = entity as? DayPlan else { break }
            dict["date"] = p.date
            dict["task_ids"] = p.taskIds

            finalBody = try ActivityParser.formatActivities(p.activities)

        default:
            break
        }

        // Add extra fields
        for (k, v) in entity.extra {
            dict[k] = v
        }

        let yamlStr = try Yams.dump(object: dict, width: -1)
        var result = "---\n\(yamlStr.trimmingCharacters(in: .whitespacesAndNewlines))\n---\n"

        if !finalBody.isEmpty {
            result.append("\n\(finalBody)")
            if !finalBody.hasSuffix("\n") {
                result.append("\n")
            }
        }

        return result
    }
}
