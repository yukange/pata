import Foundation

/// Entity reference returned from queries and searches.
public struct EntityRef: Codable, Sendable, Identifiable, Equatable {
    public var type: EntityType
    public var id: String
    public var title: String?
    public var path: String
    public var inherited: Bool
    public var time: Date
    public var status: TaskStatus?
    public var snippet: String?
    public var taskId: String?

    public init(
        type: EntityType,
        id: String,
        title: String? = nil,
        path: String,
        inherited: Bool = false,
        time: Date,
        status: TaskStatus? = nil,
        snippet: String? = nil,
        taskId: String? = nil
    ) {
        self.type = type
        self.id = id
        self.title = title
        self.path = path
        self.inherited = inherited
        self.time = time
        self.status = status
        self.snippet = snippet
        self.taskId = taskId
    }
}

/// Dangling reference report item.
public struct DanglingRef: Codable, Sendable, Equatable {
    public var sourceType: EntityType
    public var sourceId: String
    public var sourcePath: String
    public var targetType: EntityType
    public var targetId: String
    public var reason: String

    public init(
        sourceType: EntityType,
        sourceId: String,
        sourcePath: String,
        targetType: EntityType,
        targetId: String,
        reason: String
    ) {
        self.sourceType = sourceType
        self.sourceId = sourceId
        self.sourcePath = sourcePath
        self.targetType = targetType
        self.targetId = targetId
        self.reason = reason
    }
}

/// Activity location inside a Task or DayPlan.
public struct ActivityLocation: Codable, Sendable, Equatable {
    public var ownerType: EntityType
    public var ownerId: String
    public var path: String

    public init(ownerType: EntityType, ownerId: String, path: String) {
        self.ownerType = ownerType
        self.ownerId = ownerId
        self.path = path
    }
}

/// Tag aggregation overview item.
public struct TagSummary: Codable, Sendable, Identifiable, Equatable {
    public var id: String { name.lowercased() }
    public var name: String
    public var taskCount: Int
    public var noteCount: Int
    public var activityCount: Int
    public var totalCount: Int

    public init(name: String, taskCount: Int, noteCount: Int, activityCount: Int, totalCount: Int) {
        self.name = name
        self.taskCount = taskCount
        self.noteCount = noteCount
        self.activityCount = activityCount
        self.totalCount = totalCount
    }
}

/// In-memory fast index of all vault entities, thread-safe.
public final class MemoryIndex: @unchecked Sendable {
    private let lock = NSRecursiveLock()

    public internal(set) var vaultRoot: String = ""
    public internal(set) var tasks: [String: Task] = [:]
    public internal(set) var notes: [String: Note] = [:]
    public internal(set) var dayPlans: [String: DayPlan] = [:] // key: YYYY-MM-DD
    public internal(set) var files: [String: FileResource] = [:] // key: "files/..."
    public internal(set) var fileToID: [String: String] = [:] // absPath -> ID
    public internal(set) var idToFile: [String: String] = [:] // ID -> absPath
    public internal(set) var activityLocs: [String: ActivityLocation] = [:]
    public internal(set) var baselines: [String: FileBaseline] = [:]
    public internal(set) var danglingRefs: [DanglingRef] = []
    public internal(set) var parseErrors: [String] = []

    public init() {}

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        vaultRoot = ""
        tasks.removeAll()
        notes.removeAll()
        dayPlans.removeAll()
        files.removeAll()
        fileToID.removeAll()
        idToFile.removeAll()
        activityLocs.removeAll()
        baselines.removeAll()
        danglingRefs.removeAll()
        parseErrors.removeAll()
    }

    public func listTasks() -> [Task] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tasks.values).sorted { t1, t2 in
            if t1.createdAt != t2.createdAt {
                return t1.createdAt > t2.createdAt
            }
            return t1.id < t2.id
        }
    }

    public func getTask(_ id: String) -> Task? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[id]
    }

    public func listNotes() -> [Note] {
        lock.lock()
        defer { lock.unlock() }
        return Array(notes.values).sorted { n1, n2 in
            if n1.updatedAt != n2.updatedAt {
                return n1.updatedAt > n2.updatedAt
            }
            if n1.createdAt != n2.createdAt {
                return n1.createdAt > n2.createdAt
            }
            return n1.id < n2.id
        }
    }

    public func getNote(_ id: String) -> Note? {
        lock.lock()
        defer { lock.unlock() }
        return notes[id]
    }

    public func getDayPlan(date: String) -> DayPlan? {
        lock.lock()
        defer { lock.unlock() }
        return dayPlans[date]
    }

    public func listFiles() -> [FileResource] {
        lock.lock()
        defer { lock.unlock() }
        return Array(files.values).sorted { f1, f2 in
            if f1.name != f2.name {
                return f1.name < f2.name
            }
            return f1.path < f2.path
        }
    }

    public func getFileResource(relativePath: String) -> FileResource? {
        lock.lock()
        defer { lock.unlock() }
        return files[relativePath]
    }

    public func getActivityLocation(activityID: String) -> ActivityLocation? {
        lock.lock()
        defer { lock.unlock() }
        return activityLocs[activityID]
    }

    public func getBaseline(absPath: String) -> FileBaseline? {
        lock.lock()
        defer { lock.unlock() }
        return baselines[absPath]
    }

    public func setBaseline(absPath: String, baseline: FileBaseline) {
        lock.lock()
        defer { lock.unlock() }
        baselines[absPath] = baseline
    }

    public func listParseErrors() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return parseErrors
    }

    public func listDanglingReferences() -> [DanglingRef] {
        lock.lock()
        defer { lock.unlock() }
        return danglingRefs
    }

    // MARK: - Tag Aggregation

    public func listTags() -> [TagSummary] {
        lock.lock()
        defer { lock.unlock() }

        var displayCase: [String: String] = [:]
        var taskSets: [String: Set<String>] = [:]
        var noteSets: [String: Set<String>] = [:]
        var actSets: [String: Set<String>] = [:]

        // Tasks
        for (tid, task) in tasks {
            for tag in task.tags {
                let lower = tag.lowercased()
                if displayCase[lower] == nil { displayCase[lower] = tag }
                taskSets[lower, default: []].insert(tid)
            }
            // Task activities inherit task tags
            for act in task.activities {
                var effective = Set(act.tags.map { $0.lowercased() })
                for t in task.tags {
                    effective.insert(t.lowercased())
                }
                for lower in effective {
                    if displayCase[lower] == nil {
                        if let orig = act.tags.first(where: { $0.lowercased() == lower }) ?? task.tags.first(where: { $0.lowercased() == lower }) {
                            displayCase[lower] = orig
                        }
                    }
                    actSets[lower, default: []].insert(act.id)
                }
            }
        }

        // Notes (formal notes only, drafts have no tags)
        for (nid, note) in notes where !note.draft {
            for tag in note.tags {
                let lower = tag.lowercased()
                if displayCase[lower] == nil { displayCase[lower] = tag }
                noteSets[lower, default: []].insert(nid)
            }
        }

        // Today activities
        for (_, plan) in dayPlans {
            for act in plan.activities {
                for tag in act.tags {
                    let lower = tag.lowercased()
                    if displayCase[lower] == nil { displayCase[lower] = tag }
                    actSets[lower, default: []].insert(act.id)
                }
            }
        }

        var summaries: [TagSummary] = []
        for (lower, name) in displayCase {
            let tCount = taskSets[lower]?.count ?? 0
            let nCount = noteSets[lower]?.count ?? 0
            let aCount = actSets[lower]?.count ?? 0
            let total = tCount + nCount + aCount
            if total > 0 {
                summaries.append(TagSummary(
                    name: name,
                    taskCount: tCount,
                    noteCount: nCount,
                    activityCount: aCount,
                    totalCount: total
                ))
            }
        }

        return summaries.sorted { s1, s2 in
            s1.name.localizedStandardCompare(s2.name) == .orderedAscending
        }
    }

    public func findByTag(_ tag: String) -> [EntityRef] {
        lock.lock()
        defer { lock.unlock() }

        let target = tag.lowercased()
        var results: [EntityRef] = []

        // Tasks
        for (tid, task) in tasks {
            let path = idToFile[tid] ?? ""
            if task.tags.contains(where: { $0.lowercased() == target }) {
                results.append(EntityRef(
                    type: .task,
                    id: tid,
                    title: task.title,
                    path: relPath(path),
                    time: task.createdAt,
                    status: task.status,
                    snippet: task.description
                ))
            }

            // Task Activities
            let taskHasTag = task.tags.contains(where: { $0.lowercased() == target })
            for act in task.activities {
                let actHasTag = act.tags.contains(where: { $0.lowercased() == target })
                if actHasTag || taskHasTag {
                    results.append(EntityRef(
                        type: .activity,
                        id: act.id,
                        title: task.title,
                        path: relPath(path),
                        inherited: !actHasTag && taskHasTag,
                        time: act.at,
                        snippet: act.body,
                        taskId: tid
                    ))
                }
            }
        }

        // Notes
        for (nid, note) in notes where !note.draft {
            if note.tags.contains(where: { $0.lowercased() == target }) {
                let path = idToFile[nid] ?? ""
                results.append(EntityRef(
                    type: .note,
                    id: nid,
                    title: note.title,
                    path: relPath(path),
                    time: note.updatedAt,
                    snippet: note.body
                ))
            }
        }

        // Today Activities
        for (_, plan) in dayPlans {
            let path = idToFile[plan.date] ?? ""
            for act in plan.activities {
                if act.tags.contains(where: { $0.lowercased() == target }) {
                    results.append(EntityRef(
                        type: .activity,
                        id: act.id,
                        title: nil,
                        path: relPath(path),
                        time: act.at,
                        snippet: act.body
                    ))
                }
            }
        }

        return results.sorted { $0.time > $1.time }
    }

    // MARK: - Search

    public func searchAll(_ query: String) -> [EntityRef] {
        lock.lock()
        defer { lock.unlock() }

        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return [] }

        var results: [EntityRef] = []

        // Tasks
        for (tid, task) in tasks {
            let path = idToFile[tid] ?? ""
            let matchTitle = task.title.lowercased().contains(q)
            let matchDesc = task.description.lowercased().contains(q)
            if matchTitle || matchDesc {
                results.append(EntityRef(
                    type: .task,
                    id: tid,
                    title: task.title,
                    path: relPath(path),
                    time: task.updatedAt,
                    status: task.status,
                    snippet: task.description
                ))
            }

            // Task Activities
            for act in task.activities {
                if act.body.lowercased().contains(q) {
                    results.append(EntityRef(
                        type: .activity,
                        id: act.id,
                        title: task.title,
                        path: relPath(path),
                        time: act.at,
                        snippet: act.body,
                        taskId: tid
                    ))
                }
            }
        }

        // Notes (including drafts)
        for (nid, note) in notes {
            let path = idToFile[nid] ?? ""
            let matchTitle = !note.draft && note.title.lowercased().contains(q)
            let matchBody = note.body.lowercased().contains(q)
            if matchTitle || matchBody {
                results.append(EntityRef(
                    type: .note,
                    id: nid,
                    title: note.draft ? nil : note.title,
                    path: relPath(path),
                    time: note.updatedAt,
                    snippet: note.body
                ))
            }
        }

        // Today Activities
        for (_, plan) in dayPlans {
            let path = idToFile[plan.date] ?? ""
            for act in plan.activities {
                if act.body.lowercased().contains(q) {
                    results.append(EntityRef(
                        type: .activity,
                        id: act.id,
                        title: nil,
                        path: relPath(path),
                        time: act.at,
                        snippet: act.body
                    ))
                }
            }
        }

        // Files
        for (rel, file) in files {
            if file.name.lowercased().contains(q) || rel.lowercased().contains(q) {
                results.append(EntityRef(
                    type: .file,
                    id: rel,
                    title: file.name,
                    path: rel,
                    time: file.modTime
                ))
            }
        }

        return results.sorted { $0.time > $1.time }
    }

    // MARK: - Links and Candidates

    public func listNoteRefs() -> [NoteRef] {
        lock.lock()
        defer { lock.unlock() }

        var candidates: [NoteRef] = []
        for (id, note) in notes where !note.draft {
            let path = idToFile[id] ?? ""
            candidates.append(NoteRef(id: id, title: note.title, path: relPath(path)))
        }

        return candidates.sorted { r1, r2 in
            if r1.title != r2.title {
                return r1.title.localizedStandardCompare(r2.title) == .orderedAscending
            }
            return r1.path < r2.path
        }
    }

    public func backlinks(targetID: String) -> [LinkSource] {
        lock.lock()
        defer { lock.unlock() }

        guard notes[targetID] != nil else { return [] }

        var sources: [LinkSource] = []
        var seen: Set<String> = []

        func addSource(type: EntityType, id: String, title: String, path: String) {
            let key = "\(type.rawValue):\(id)"
            if !seen.contains(key) {
                seen.insert(key)
                sources.append(LinkSource(type: type, id: id, title: title, path: relPath(path)))
            }
        }

        // From other Notes
        for (id, n) in notes where id != targetID {
            let notePath = idToFile[id] ?? ""
            let noteDir = URL(fileURLWithPath: notePath).deletingLastPathComponent().path

            for dest in Links.noteLinkDests(body: n.body) {
                let candidateAbs = URL(fileURLWithPath: dest, relativeTo: URL(fileURLWithPath: noteDir)).standardized.path
                if let matchedID = fileToID[candidateAbs], matchedID == targetID {
                    addSource(type: .note, id: id, title: n.title, path: notePath)
                    break
                }
            }
        }

        // From Tasks
        for (tid, t) in tasks {
            let tPath = idToFile[tid] ?? ""
            if t.noteIds.contains(targetID) {
                addSource(type: .task, id: tid, title: t.title, path: tPath)
            }
            if textRefsHit(body: t.description, refs: t.noteRefs, target: targetID) {
                addSource(type: .task, id: tid, title: t.title, path: tPath)
            }
            for act in t.activities {
                if textRefsHit(body: act.body, refs: act.noteRefs, target: targetID) {
                    addSource(type: .task, id: tid, title: t.title, path: tPath)
                    break
                }
            }
        }

        return sources.sorted { s1, s2 in
            if s1.title != s2.title {
                return s1.title.localizedStandardCompare(s2.title) == .orderedAscending
            }
            return s1.path < s2.path
        }
    }

    private func textRefsHit(body: String, refs: [String: String], target: String) -> Bool {
        for key in Links.textRefKeys(body: body) {
            if Links.resolveTextRef(name: key, noteRefs: refs, notes: notes) == target {
                return true
            }
        }
        return false
    }

    // MARK: - Internal Mutations

    public func updateEntity(_ entity: any Entity, path: String, baseline: FileBaseline) {
        lock.lock()
        defer { lock.unlock() }

        let absPath = URL(fileURLWithPath: path).standardized.path

        // Check for duplicate entity ID collision across different files
        if let existingPath = idToFile[entity.id], existingPath != absPath {
            parseErrors.append("duplicate entity ID collision: ID '\(entity.id)' already mapped to \(existingPath), ignoring conflicting file at \(absPath)")
            return
        }

        // Clean up previous activity locations for this file
        activityLocs = activityLocs.filter { $0.value.path != absPath }

        fileToID[absPath] = entity.id
        idToFile[entity.id] = absPath
        baselines[absPath] = baseline

        switch entity.type {
        case .task:
            guard let task = entity as? Task else { return }
            tasks[task.id] = task
            for act in task.activities {
                activityLocs[act.id] = ActivityLocation(ownerType: .task, ownerId: task.id, path: absPath)
            }
        case .note:
            guard let note = entity as? Note else { return }
            notes[note.id] = note
        case .dayPlan:
            guard let plan = entity as? DayPlan else { return }
            dayPlans[plan.date] = plan
            for act in plan.activities {
                activityLocs[act.id] = ActivityLocation(ownerType: .dayPlan, ownerId: plan.date, path: absPath)
            }
        default:
            break
        }

        recomputeDanglingRefsLocked()
    }

    public func removeFile(absPath: String) {
        lock.lock()
        defer { lock.unlock() }

        let standard = URL(fileURLWithPath: absPath).standardized.path
        guard let id = fileToID[standard] else {
            // Might be file resource
            if let rel = toRelSlash(standard) {
                files.removeValue(forKey: rel)
            }
            baselines.removeValue(forKey: standard)
            return
        }

        fileToID.removeValue(forKey: standard)
        idToFile.removeValue(forKey: id)
        baselines.removeValue(forKey: standard)

        tasks.removeValue(forKey: id)
        notes.removeValue(forKey: id)
        dayPlans.removeValue(forKey: id)

        activityLocs = activityLocs.filter { $0.value.path != standard }

        recomputeDanglingRefsLocked()
    }

    private func recomputeDanglingRefsLocked() {
        var dangling: [DanglingRef] = []

        // 1. Tasks referencing non-existent notes
        for (id, t) in tasks {
            for noteID in t.noteIds {
                if notes[noteID] == nil {
                    dangling.append(DanglingRef(
                        sourceType: .task,
                        sourceId: id,
                        sourcePath: idToFile[id] ?? "",
                        targetType: .note,
                        targetId: noteID,
                        reason: "referenced note '\(noteID)' not found"
                    ))
                }
            }
        }

        // 2. DayPlans referencing non-existent tasks
        for (date, p) in dayPlans {
            for taskID in p.taskIds {
                if tasks[taskID] == nil {
                    dangling.append(DanglingRef(
                        sourceType: .dayPlan,
                        sourceId: date,
                        sourcePath: idToFile[date] ?? "",
                        targetType: .task,
                        targetId: taskID,
                        reason: "planned task '\(taskID)' not found"
                    ))
                }
            }
        }

        danglingRefs = dangling
    }

    public func updateFileResource(_ res: FileResource) {
        lock.lock()
        defer { lock.unlock() }
        files[res.path] = res
    }

    private func relPath(_ abs: String) -> String {
        guard !vaultRoot.isEmpty, abs.hasPrefix(vaultRoot) else { return abs }
        let sub = abs.dropFirst(vaultRoot.count)
        if sub.hasPrefix("/") {
            return String(sub.dropFirst())
        }
        return String(sub)
    }

    private func toRelSlash(_ abs: String) -> String? {
        guard !vaultRoot.isEmpty, abs.hasPrefix(vaultRoot) else { return nil }
        let sub = abs.dropFirst(vaultRoot.count)
        let s = sub.hasPrefix("/") ? String(sub.dropFirst()) : String(sub)
        return s.replacingOccurrences(of: "\\", with: "/")
    }
}
