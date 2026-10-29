import Foundation

public let SourceAgent = "agent"

/// EntityType represents the type of a Pata entity.
public enum EntityType: String, Codable, Sendable {
    case task = "task"
    case note = "note"
    case dayPlan = "day_plan"
    case activity = "activity"
    case file = "file"
}

/// TaskStatus represents the current status of a task.
public enum TaskStatus: String, Codable, Sendable {
    case todo = "todo"
    case done = "done"
    case doing = "doing" // Legacy status, treated as todo
}

/// StatusEventAction represents actions recorded in task status events.
public enum StatusEventAction: String, Codable, Sendable {
    case completed = "completed"
    case reopened = "reopened"
}

/// StatusEvent records completion and reopen events.
public struct StatusEvent: Codable, Sendable, Equatable {
    public var action: StatusEventAction
    public var at: Date
    public var by: String?

    public init(action: StatusEventAction, at: Date, by: String? = nil) {
        self.action = action
        self.at = at
        self.by = by
    }
}

/// Activity represents an embedded activity inside a Task or DayPlan.
public struct Activity: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var at: Date
    public var by: String?
    public var tags: [String]
    public var noteRefs: [String: String]
    public var body: String
    public var taskId: String?
    public var extra: [String: String]

    public init(
        id: String,
        at: Date,
        by: String? = nil,
        tags: [String] = [],
        noteRefs: [String: String] = [:],
        body: String = "",
        taskId: String? = nil,
        extra: [String: String] = [:]
    ) {
        self.id = id
        self.at = at
        self.by = by
        self.tags = tags
        self.noteRefs = noteRefs
        self.body = body
        self.taskId = taskId
        self.extra = extra
    }
}

/// Common protocol for all Pata top-level markdown entities.
public protocol Entity: Sendable {
    var type: EntityType { get }
    var id: String { get }
    var body: String { get set }
    var extra: [String: String] { get set }
    func clone() -> any Entity
}

/// Task represents a task item.
public struct Task: Entity, Codable, Sendable, Identifiable, Equatable {
    public var type: EntityType { .task }
    public var id: String
    public var title: String
    public var description: String
    public var status: TaskStatus
    public var completedAt: Date?
    public var due: String? // YYYY-MM-DD or nil
    public var tags: [String]
    public var noteIds: [String]
    public var noteRefs: [String: String]
    public var createdAt: Date
    public var createdBy: String?
    public var updatedAt: Date
    public var statusEvents: [StatusEvent]
    public var extra: [String: String]
    public var body: String
    public var activities: [Activity]

    public init(
        id: String,
        title: String,
        description: String = "",
        status: TaskStatus = .todo,
        completedAt: Date? = nil,
        due: String? = nil,
        tags: [String] = [],
        noteIds: [String] = [],
        noteRefs: [String: String] = [:],
        createdAt: Date = Date(),
        createdBy: String? = nil,
        updatedAt: Date = Date(),
        statusEvents: [StatusEvent] = [],
        extra: [String: String] = [:],
        body: String = "",
        activities: [Activity] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status == .doing ? .todo : status
        self.completedAt = completedAt
        self.due = due
        self.tags = tags
        self.noteIds = noteIds
        self.noteRefs = noteRefs
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.statusEvents = statusEvents
        self.extra = extra
        self.body = body
        self.activities = activities
    }

    public func clone() -> any Entity {
        return self
    }
}

/// Note represents a markdown note (formal or draft).
public struct Note: Entity, Codable, Sendable, Identifiable, Equatable {
    public var type: EntityType { .note }
    public var id: String
    public var draft: Bool
    public var title: String
    public var tags: [String]
    public var audioFile: String?
    public var audioTranscript: Bool
    public var createdAt: Date
    public var createdBy: String?
    public var updatedAt: Date
    public var extra: [String: String]
    public var body: String

    public init(
        id: String,
        draft: Bool = false,
        title: String = "",
        tags: [String] = [],
        audioFile: String? = nil,
        audioTranscript: Bool = false,
        createdAt: Date = Date(),
        createdBy: String? = nil,
        updatedAt: Date = Date(),
        extra: [String: String] = [:],
        body: String = ""
    ) {
        self.id = id
        self.draft = draft
        self.title = title
        self.tags = tags
        self.audioFile = audioFile
        self.audioTranscript = audioTranscript
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.updatedAt = updatedAt
        self.extra = extra
        self.body = body
    }

    public func clone() -> any Entity {
        return self
    }
}

/// DayPlan represents a daily plan stored in plans/YYYY-MM-DD.md.
public struct DayPlan: Entity, Codable, Sendable, Identifiable, Equatable {
    public var type: EntityType { .dayPlan }
    public var id: String { date }
    public var date: String // YYYY-MM-DD
    public var taskIds: [String]
    public var extra: [String: String]
    public var body: String
    public var activities: [Activity]

    public init(
        date: String,
        taskIds: [String] = [],
        extra: [String: String] = [:],
        body: String = "",
        activities: [Activity] = []
    ) {
        self.date = date
        self.taskIds = taskIds
        self.extra = extra
        self.body = body
        self.activities = activities
    }

    public func clone() -> any Entity {
        return self
    }
}

/// FileResource represents an ordinary binary or document file in files/.
public struct FileResource: Codable, Sendable, Equatable {
    public var path: String    // Vault-relative path with forward slashes (e.g. "files/doc.pdf")
    public var name: String    // Base filename (e.g. "doc.pdf")
    public var ext: String     // Extension including dot (e.g. ".pdf")
    public var size: Int64     // File size in bytes
    public var modTime: Date   // Last modification time

    public init(path: String, name: String, ext: String, size: Int64, modTime: Date) {
        self.path = path
        self.name = name
        self.ext = ext
        self.size = size
        self.modTime = modTime
    }
}

/// FileBaseline records file identity and content baseline for optimistic concurrency.
public struct FileBaseline: Codable, Sendable, Equatable {
    public var path: String
    public var hash: String
    public var modTime: Date

    public init(path: String, hash: String, modTime: Date) {
        self.path = path
        self.hash = hash
        self.modTime = modTime
    }
}
