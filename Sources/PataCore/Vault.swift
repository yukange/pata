import Foundation

public struct VaultEvent: Sendable {
    public var op: String // "create", "update", "delete", "error"
    public var path: String
    public var entityId: String?
    public var type: EntityType?
    public var err: (any Error)?

    public init(op: String, path: String, entityId: String? = nil, type: EntityType? = nil, err: (any Error)? = nil) {
        self.op = op
        self.path = path
        self.entityId = entityId
        self.type = type
        self.err = err
    }
}

public final class Vault: @unchecked Sendable {
    public let rootPath: String
    public let index: MemoryIndex
    public let tracker: WriteTracker

    public var onEvent: (@Sendable (VaultEvent) -> Void)?

    private let mutationLock = NSLock()
    private var isWatching = false
    private var watcherSources: [DispatchSourceFileSystemObject] = []

    public init(rootPath: String) throws {
        let absRoot = URL(fileURLWithPath: rootPath).standardized.path
        self.rootPath = absRoot
        self.index = MemoryIndex()
        self.tracker = WriteTracker(retention: 3.0)

        try FileManager.default.createDirectory(atPath: absRoot, withIntermediateDirectories: true)
        for dir in ["tasks", "notes", "plans", "files"] {
            let p = (absRoot as NSString).appendingPathComponent(dir)
            try FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        }

        try rescan()
    }

    deinit {
        stopWatcher()
    }

    // MARK: - Rescan

    public func rescan() throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        index.clear()
        index.vaultRoot = rootPath

        // 1. Scan tasks/
        let tasksDir = (rootPath as NSString).appendingPathComponent("tasks")
        if let taskFiles = try? FileManager.default.contentsOfDirectory(atPath: tasksDir) {
            for f in taskFiles.sorted() where f.hasSuffix(".md") {
                let absPath = (tasksDir as NSString).appendingPathComponent(f)
                do {
                    let (baseline, data) = try Safety.readBaseline(absPath: absPath)
                    guard let text = String(data: data, encoding: .utf8) else { continue }
                    let entity = try Frontmatter.parseMarkdown(filePath: absPath, content: text)
                    index.updateEntity(entity, path: absPath, baseline: baseline)
                } catch {
                    index.parseErrors.append("Failed to parse \(absPath): \(error)")
                }
            }
        }

        // 2. Scan notes/ (recursively)
        let notesDir = (rootPath as NSString).appendingPathComponent("notes")
        scanNotesDirectory(notesDir)

        // 3. Scan plans/
        let plansDir = (rootPath as NSString).appendingPathComponent("plans")
        if let planFiles = try? FileManager.default.contentsOfDirectory(atPath: plansDir) {
            for f in planFiles.sorted() where f.hasSuffix(".md") {
                let absPath = (plansDir as NSString).appendingPathComponent(f)
                do {
                    let (baseline, data) = try Safety.readBaseline(absPath: absPath)
                    guard let text = String(data: data, encoding: .utf8) else { continue }
                    let entity = try Frontmatter.parseMarkdown(filePath: absPath, content: text)
                    index.updateEntity(entity, path: absPath, baseline: baseline)
                } catch {
                    index.parseErrors.append("Failed to parse \(absPath): \(error)")
                }
            }
        }

        // 4. Scan files/ (recursively)
        let filesDir = (rootPath as NSString).appendingPathComponent("files")
        scanFilesDirectory(filesDir)
    }

    private func scanFilesDirectory(_ dir: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for item in items where !item.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    scanFilesDirectory(fullPath)
                } else {
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64,
                       let modTime = attrs[.modificationDate] as? Date {
                        let ext = (item as NSString).pathExtension
                        let rel = fullPath.hasPrefix(rootPath + "/") ? String(fullPath.dropFirst(rootPath.count + 1)) : "files/\(item)"
                        let res = FileResource(
                            path: rel,
                            name: item,
                            ext: ext.isEmpty ? "" : ".\(ext)",
                            size: size,
                            modTime: modTime
                        )
                        index.updateFileResource(res)
                    }
                }
            }
        }
    }

    private func scanNotesDirectory(_ dir: String) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        for item in items where !item.hasPrefix(".") {
            let fullPath = (dir as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) {
                if isDir.boolValue {
                    scanNotesDirectory(fullPath)
                } else if item.hasSuffix(".md") {
                    do {
                        let (baseline, data) = try Safety.readBaseline(absPath: fullPath)
                        guard let text = String(data: data, encoding: .utf8) else { continue }
                        let entity = try Frontmatter.parseMarkdown(filePath: fullPath, content: text)
                        index.updateEntity(entity, path: fullPath, baseline: baseline)
                    } catch {
                        index.parseErrors.append("Failed to parse \(fullPath): \(error)")
                    }
                }
            }
        }
    }

    public func resolveEntityPath(_ entity: any Entity) -> String {
        if let existing = index.idToFile[entity.id] {
            return existing
        }
        let filename = ULID.formatEntityFilename(entity)
        switch entity.type {
        case .task:
            return (rootPath as NSString).appendingPathComponent("tasks/\(filename)")
        case .note:
            return (rootPath as NSString).appendingPathComponent("notes/\(filename)")
        case .dayPlan:
            return (rootPath as NSString).appendingPathComponent("plans/\(filename)")
        default:
            return (rootPath as NSString).appendingPathComponent("\(filename)")
        }
    }

    // MARK: - Task CRUD

    public func createTask(
        title: String,
        description: String = "",
        status: TaskStatus = .todo,
        due: String? = nil,
        tags: [String] = [],
        noteIds: [String] = [],
        noteRefs: [String: String] = [:],
        source: String? = nil
    ) throws -> Task {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let id = ULID.generateEntityID(type: .task)
        let now = Date()
        var statusEvents: [StatusEvent] = []
        var completedAt: Date? = nil

        if status == .done {
            completedAt = now
            statusEvents.append(StatusEvent(action: .completed, at: now, by: source))
        }

        let task = Task(
            id: id,
            title: title,
            description: description,
            status: status,
            completedAt: completedAt,
            due: due,
            tags: tags,
            noteIds: noteIds,
            noteRefs: noteRefs,
            createdAt: now,
            createdBy: source,
            updatedAt: now,
            statusEvents: statusEvents,
            extra: [:],
            body: "",
            activities: []
        )

        let targetPath = resolveEntityPath(task)
        let md = try Frontmatter.serializeMarkdown(task)
        let baseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: nil, tracker: tracker)
        index.updateEntity(task, path: targetPath, baseline: baseline)

        onEvent?(VaultEvent(op: "create", path: targetPath, entityId: id, type: .task))
        return task
    }

    public func updateTask(_ task: Task, baseline: FileBaseline? = nil) throws -> Task {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var t = task
        t.updatedAt = Date()

        // Preserve any concurrent activities added to this task in the index
        if let existing = index.getTask(t.id), t.activities.count < existing.activities.count {
            t.activities = existing.activities
        }

        let targetPath = resolveEntityPath(t)
        let base = baseline ?? index.getBaseline(absPath: targetPath)

        let md = try Frontmatter.serializeMarkdown(t)
        let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
        index.updateEntity(t, path: targetPath, baseline: newBaseline)

        onEvent?(VaultEvent(op: "update", path: targetPath, entityId: t.id, type: .task))
        return t
    }

    public func setTaskStatus(id: String, status: TaskStatus, source: String? = nil) throws -> Task {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard var task = index.getTask(id) else {
            throw SchemaError.validationError(field: "id", reason: "task '\(id)' not found")
        }

        let targetStatus: TaskStatus = status == .doing ? .todo : status
        if task.status == targetStatus {
            return task
        }

        let now = Date()
        task.status = targetStatus
        task.updatedAt = now

        if targetStatus == .done {
            task.completedAt = now
            task.statusEvents.append(StatusEvent(action: .completed, at: now, by: source))
        } else {
            task.completedAt = nil
            task.statusEvents.append(StatusEvent(action: .reopened, at: now, by: source))
        }

        let targetPath = resolveEntityPath(task)
        let base = index.getBaseline(absPath: targetPath)
        let md = try Frontmatter.serializeMarkdown(task)
        let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
        index.updateEntity(task, path: targetPath, baseline: newBaseline)

        onEvent?(VaultEvent(op: "update", path: targetPath, entityId: id, type: .task))
        return task
    }

    public func deleteTask(id: String) throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let path = index.idToFile[id] else { return }

        // Remove file
        try? FileManager.default.removeItem(atPath: path)
        index.removeFile(absPath: path)

        // Clean task ID from all DayPlans
        for (_, var plan) in index.dayPlans {
            if plan.taskIds.contains(id) {
                plan.taskIds.removeAll { $0 == id }
                let planPath = resolveEntityPath(plan)
                let base = index.getBaseline(absPath: planPath)
                if let md = try? Frontmatter.serializeMarkdown(plan),
                   let newBase = try? Safety.safeWrite(targetPath: planPath, data: Data(md.utf8), baseline: base, tracker: tracker) {
                    index.updateEntity(plan, path: planPath, baseline: newBase)
                }
            }
        }

        onEvent?(VaultEvent(op: "delete", path: path, entityId: id, type: .task))
    }

    // MARK: - Note CRUD

    public func createNote(
        title: String = "",
        body: String = "",
        tags: [String] = [],
        draft: Bool = false,
        audioFile: String? = nil,
        audioTranscript: Bool = false,
        source: String? = nil
    ) throws -> Note {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let id = ULID.generateEntityID(type: .note)
        let now = Date()

        let note = Note(
            id: id,
            draft: draft,
            title: title,
            tags: draft ? [] : tags,
            audioFile: audioFile,
            audioTranscript: audioTranscript,
            createdAt: now,
            createdBy: source,
            updatedAt: now,
            extra: [:],
            body: body
        )

        let targetPath = resolveEntityPath(note)
        let md = try Frontmatter.serializeMarkdown(note)
        let baseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: nil, tracker: tracker)
        index.updateEntity(note, path: targetPath, baseline: baseline)

        onEvent?(VaultEvent(op: "create", path: targetPath, entityId: id, type: .note))
        return note
    }

    public func updateNote(_ note: Note, baseline: FileBaseline? = nil) throws -> Note {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        var n = note
        n.updatedAt = Date()

        let targetPath = resolveEntityPath(n)
        let base = baseline ?? index.getBaseline(absPath: targetPath)

        let md = try Frontmatter.serializeMarkdown(n)
        let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
        index.updateEntity(n, path: targetPath, baseline: newBaseline)

        onEvent?(VaultEvent(op: "update", path: targetPath, entityId: n.id, type: .note))
        return n
    }

    /// In-place conversion from Draft to Formal Note.
    /// Preserves original Note ID, file path, created_at, body, and audio metadata.
    public func convertDraftToNote(id: String, newTitle: String, tags: [String] = []) throws -> Note {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard var note = index.getNote(id) else {
            throw SchemaError.validationError(field: "id", reason: "note '\(id)' not found")
        }

        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw SchemaError.validationError(field: "title", reason: "cannot be empty when converting to note")
        }

        note.draft = false
        note.title = trimmedTitle
        note.tags = tags
        note.updatedAt = Date()

        let targetPath = resolveEntityPath(note)
        let base = index.getBaseline(absPath: targetPath)

        let md = try Frontmatter.serializeMarkdown(note)
        let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
        index.updateEntity(note, path: targetPath, baseline: newBaseline)

        onEvent?(VaultEvent(op: "update", path: targetPath, entityId: id, type: .note))
        return note
    }

    public func deleteNote(id: String) throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let path = index.idToFile[id] else { return }
        try? FileManager.default.removeItem(atPath: path)
        index.removeFile(absPath: path)

        onEvent?(VaultEvent(op: "delete", path: path, entityId: id, type: .note))
    }

    // MARK: - DayPlan CRUD

    public func getDayPlan(date: String) -> DayPlan {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        if let existing = index.dayPlans[date] {
            return existing
        }
        return DayPlan(date: date, taskIds: [], extra: [:], body: "", activities: [])
    }

    public func updateDayPlan(_ plan: DayPlan, baseline: FileBaseline? = nil) throws -> DayPlan {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let targetPath = resolveEntityPath(plan)
        let base = baseline ?? index.getBaseline(absPath: targetPath)

        let md = try Frontmatter.serializeMarkdown(plan)
        let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
        index.updateEntity(plan, path: targetPath, baseline: newBaseline)

        onEvent?(VaultEvent(op: "update", path: targetPath, entityId: plan.date, type: .dayPlan))
        return plan
    }

    public func addTaskToPlan(date: String, taskId: String) throws {
        var plan = getDayPlan(date: date)
        if !plan.taskIds.contains(taskId) {
            plan.taskIds.append(taskId)
            _ = try updateDayPlan(plan)
        }
    }

    public func removeTaskFromPlan(date: String, taskId: String) throws {
        var plan = getDayPlan(date: date)
        plan.taskIds.removeAll { $0 == taskId }
        _ = try updateDayPlan(plan)
    }

    // MARK: - Activity Operations

    public func createActivity(
        taskId: String? = nil,
        date: String? = nil,
        body: String,
        tags: [String] = [],
        noteRefs: [String: String] = [:],
        source: String? = nil
    ) throws -> Activity {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let activityId = ULID.generateActivityID()
        let now = Date()

        let act = Activity(
            id: activityId,
            at: now,
            by: source,
            tags: tags,
            noteRefs: noteRefs,
            body: body,
            taskId: taskId
        )

        if let tid = taskId, !tid.isEmpty {
            guard var task = index.getTask(tid) else {
                throw SchemaError.validationError(field: "taskId", reason: "task '\(tid)' not found")
            }
            task.activities.append(act)
            task.updatedAt = now

            let targetPath = resolveEntityPath(task)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(task)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(task, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: tid, type: .task))
        } else {
            let planDate: String
            if let d = date, !d.isEmpty {
                planDate = d
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                planDate = formatter.string(from: now)
            }

            var plan = index.dayPlans[planDate] ?? DayPlan(date: planDate, taskIds: [], extra: [:], body: "", activities: [])
            plan.activities.append(act)

            let targetPath = resolveEntityPath(plan)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(plan)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(plan, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: planDate, type: .dayPlan))
        }

        return act
    }

    public func updateActivity(
        id: String,
        body: String,
        tags: [String]? = nil,
        noteRefs: [String: String]? = nil
    ) throws -> Activity {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let loc = index.getActivityLocation(activityID: id) else {
            throw SchemaError.validationError(field: "id", reason: "activity '\(id)' not found")
        }

        let now = Date()

        switch loc.ownerType {
        case .task:
            guard var task = index.getTask(loc.ownerId) else {
                throw SchemaError.validationError(field: "taskId", reason: "task '\(loc.ownerId)' not found")
            }
            guard let idx = task.activities.firstIndex(where: { $0.id == id }) else {
                throw SchemaError.validationError(field: "id", reason: "activity '\(id)' not found in task")
            }

            task.activities[idx].body = body
            if let t = tags { task.activities[idx].tags = t }
            if let r = noteRefs { task.activities[idx].noteRefs = r }
            task.updatedAt = now

            let updatedAct = task.activities[idx]
            let targetPath = resolveEntityPath(task)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(task)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(task, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: task.id, type: .task))
            return updatedAct

        case .dayPlan:
            guard var plan = index.getDayPlan(date: loc.ownerId) else {
                throw SchemaError.validationError(field: "date", reason: "day_plan '\(loc.ownerId)' not found")
            }
            guard let idx = plan.activities.firstIndex(where: { $0.id == id }) else {
                throw SchemaError.validationError(field: "id", reason: "activity '\(id)' not found in day_plan")
            }

            plan.activities[idx].body = body
            if let t = tags { plan.activities[idx].tags = t }
            if let r = noteRefs { plan.activities[idx].noteRefs = r }

            let updatedAct = plan.activities[idx]
            let targetPath = resolveEntityPath(plan)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(plan)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(plan, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: plan.date, type: .dayPlan))
            return updatedAct

        default:
            throw SchemaError.validationError(field: "ownerType", reason: "unsupported activity owner")
        }
    }

    public func deleteActivity(id: String) throws {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        guard let loc = index.getActivityLocation(activityID: id) else { return }

        switch loc.ownerType {
        case .task:
            guard var task = index.getTask(loc.ownerId) else { return }
            task.activities.removeAll { $0.id == id }
            task.updatedAt = Date()

            let targetPath = resolveEntityPath(task)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(task)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(task, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: task.id, type: .task))

        case .dayPlan:
            guard var plan = index.getDayPlan(date: loc.ownerId) else { return }
            plan.activities.removeAll { $0.id == id }

            let targetPath = resolveEntityPath(plan)
            let base = index.getBaseline(absPath: targetPath)
            let md = try Frontmatter.serializeMarkdown(plan)
            let newBaseline = try Safety.safeWrite(targetPath: targetPath, data: Data(md.utf8), baseline: base, tracker: tracker)
            index.updateEntity(plan, path: targetPath, baseline: newBaseline)

            onEvent?(VaultEvent(op: "update", path: targetPath, entityId: plan.date, type: .dayPlan))

        default:
            break
        }
    }

    // MARK: - File Import

    /// Imports a file into `files/` without overwriting existing files.
    /// Returns the vault-relative path (e.g. "files/audio.mp3").
    public func importFile(sourceURL: URL, destFilename: String? = nil) throws -> String {
        mutationLock.lock()
        defer { mutationLock.unlock() }

        let originalName = destFilename ?? sourceURL.lastPathComponent
        let baseExt = (originalName as NSString).pathExtension
        let baseStem = (originalName as NSString).deletingPathExtension

        let filesDir = (rootPath as NSString).appendingPathComponent("files")
        try FileManager.default.createDirectory(atPath: filesDir, withIntermediateDirectories: true)

        var candidateName = originalName
        var candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
        var counter = 1

        while FileManager.default.fileExists(atPath: candidatePath) {
            candidateName = "\(baseStem)_\(counter).\(baseExt)"
            candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
            counter += 1
        }

        try FileManager.default.copyItem(at: sourceURL, to: URL(fileURLWithPath: candidatePath))

        let attrs = try FileManager.default.attributesOfItem(atPath: candidatePath)
        let size = (attrs[.size] as? Int64) ?? 0
        let modTime = (attrs[.modificationDate] as? Date) ?? Date()

        let relPath = "files/\(candidateName)"
        let res = FileResource(
            path: relPath,
            name: candidateName,
            ext: baseExt.isEmpty ? "" : ".\(baseExt)",
            size: size,
            modTime: modTime
        )
        index.updateFileResource(res)

        onEvent?(VaultEvent(op: "create", path: candidatePath, type: .file))
        return relPath
    }

    // MARK: - File System Watcher

    public func startWatcher() {
        guard !isWatching else { return }
        isWatching = true

        let dirs = ["tasks", "notes", "plans", "files"]
        for dir in dirs {
            let path = (rootPath as NSString).appendingPathComponent(dir)
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .link, .rename],
                queue: DispatchQueue.global(qos: .utility)
            )

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                try? self.rescan()
                self.onEvent?(VaultEvent(op: "update", path: path))
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            watcherSources.append(source)
        }
    }

    public func stopWatcher() {
        guard isWatching else { return }
        isWatching = false
        for s in watcherSources {
            s.cancel()
        }
        watcherSources.removeAll()
    }
}
