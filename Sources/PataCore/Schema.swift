import Foundation

public enum SchemaError: LocalizedError, Equatable {
    case parseError(String, path: String? = nil)
    case validationError(field: String, reason: String, path: String? = nil)

    public var errorDescription: String? {
        switch self {
        case .parseError(let msg, let path):
            if let p = path, !p.isEmpty {
                return "parse error at \(p): \(msg)"
            }
            return "parse error: \(msg)"
        case .validationError(let field, let reason, let path):
            if let p = path, !p.isEmpty {
                return "validation error at \(p): field '\(field)' \(reason)"
            }
            return "validation error: field '\(field)' \(reason)"
        }
    }
}

public struct SchemaValidator {
    public static func validateEntity(_ entity: Entity, path: String = "") throws {
        switch entity.type {
        case .task:
            guard let task = entity as? Task else {
                throw SchemaError.validationError(field: "type", reason: "entity type mismatch", path: path)
            }
            try validateTask(task, path: path)
        case .note:
            guard let note = entity as? Note else {
                throw SchemaError.validationError(field: "type", reason: "entity type mismatch", path: path)
            }
            try validateNote(note, path: path)
        case .dayPlan:
            guard let plan = entity as? DayPlan else {
                throw SchemaError.validationError(field: "type", reason: "entity type mismatch", path: path)
            }
            try validateDayPlan(plan, path: path)
        default:
            throw SchemaError.validationError(field: "type", reason: "unsupported entity type '\(entity.type.rawValue)'", path: path)
        }
    }

    private static func validateSource(_ source: String?, field: String, path: String) throws {
        if let s = source, !s.isEmpty {
            guard s == SourceAgent else {
                throw SchemaError.validationError(field: field, reason: "must be 'agent' or omitted; got '\(s)'", path: path)
            }
        }
    }

    private static func validateDateFormat(_ d: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.date(from: d) != nil
    }

    private static func validateTask(_ t: Task, path: String) throws {
        try validateSource(t.createdBy, field: "created_by", path: path)

        if t.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SchemaError.validationError(field: "id", reason: "is required", path: path)
        }
        if t.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SchemaError.validationError(field: "title", reason: "is required", path: path)
        }

        if let due = t.due, !due.isEmpty {
            if !validateDateFormat(due) {
                throw SchemaError.validationError(field: "due", reason: "must be YYYY-MM-DD or null; got '\(due)'", path: path)
            }
        }

        for (idx, tag) in t.tags.enumerated() {
            if tag.contains("#") {
                throw SchemaError.validationError(field: "tags[\(idx)]", reason: "must not contain '#'; got '\(tag)'", path: path)
            }
        }

        for (idx, ev) in t.statusEvents.enumerated() {
            try validateSource(ev.by, field: "status_events[\(idx)].by", path: path)
        }

        try validateActivities(t.activities, path: path)
    }

    private static func validateNote(_ n: Note, path: String) throws {
        try validateSource(n.createdBy, field: "created_by", path: path)

        if n.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SchemaError.validationError(field: "id", reason: "is required", path: path)
        }
        if !n.draft && n.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw SchemaError.validationError(field: "title", reason: "is required", path: path)
        }

        for (idx, tag) in n.tags.enumerated() {
            if tag.contains("#") {
                throw SchemaError.validationError(field: "tags[\(idx)]", reason: "must not contain '#'; got '\(tag)'", path: path)
            }
        }

        if n.audioTranscript && (n.audioFile == nil || n.audioFile!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            throw SchemaError.validationError(field: "audio_file", reason: "audio_file must be specified when audio_transcript is true", path: path)
        }

        if let audioFile = n.audioFile, !audioFile.isEmpty {
            let normalized = audioFile.replacingOccurrences(of: "\\", with: "/")
            if normalized.hasPrefix("/") || normalized.hasPrefix("../") || normalized == ".." {
                throw SchemaError.validationError(field: "audio_file", reason: "must be a valid vault-relative path; got '\(audioFile)'", path: path)
            }
        }
    }

    private static func validateDayPlan(_ p: DayPlan, path: String) throws {
        if !validateDateFormat(p.date) {
            throw SchemaError.validationError(field: "date", reason: "must be YYYY-MM-DD; got '\(p.date)'", path: path)
        }

        var seen: Set<String> = []
        for (idx, taskId) in p.taskIds.enumerated() {
            let trimmed = taskId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                throw SchemaError.validationError(field: "task_ids[\(idx)]", reason: "task id cannot be empty", path: path)
            }
            if seen.contains(trimmed) {
                throw SchemaError.validationError(field: "task_ids", reason: "duplicate task id '\(trimmed)' violated DayPlan invariant", path: path)
            }
            seen.insert(trimmed)
        }

        try validateActivities(p.activities, path: path)
    }

    private static func validateActivities(_ activities: [Activity], path: String) throws {
        var seen: Set<String> = []
        for (idx, act) in activities.enumerated() {
            try validateSource(act.by, field: "activities[\(idx)].by", path: path)

            let id = act.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty {
                throw SchemaError.validationError(field: "activities[\(idx)].id", reason: "is required", path: path)
            }
            if !id.hasPrefix("a-") || id.count <= 2 {
                throw SchemaError.validationError(field: "activities[\(idx)].id", reason: "must start with 'a-'; got '\(id)'", path: path)
            }
            if seen.contains(id) {
                throw SchemaError.validationError(field: "activities[\(idx)].id", reason: "duplicate activity ID '\(id)' in same entity", path: path)
            }
            seen.insert(id)

            for (tagIdx, tag) in act.tags.enumerated() {
                if tag.contains("#") {
                    throw SchemaError.validationError(field: "activities[\(idx)].tags[\(tagIdx)]", reason: "must not contain '#'; got '\(tag)'", path: path)
                }
            }
        }
    }
}
