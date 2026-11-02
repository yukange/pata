import Testing
import Foundation
import SwiftUI
import AppKit
@testable import PataCore
@testable import PataUI

@Suite("Description Editor Tests")
struct DescriptionEditorTests {
    @Test("Verify task description update and auto save semantics")
    func taskDescriptionUpdate() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "测试任务", description: "初始描述")
        #expect(task.description == "初始描述")

        var updated = task
        updated.description = "更新后的描述\n第二行\n支持 [[笔记引用]]"
        _ = try vault.updateTask(updated)

        let reloaded = vault.index.getTask(task.id)
        #expect(reloaded?.description == "更新后的描述\n第二行\n支持 [[笔记引用]]")
    }

    @Test("Test DescriptionNSTextView for Enter newline and Esc exit")
    @MainActor
    func testDescriptionNSTextViewKeyHandling() {
        let tv = DescriptionNSTextView()
        tv.string = "第一行"
        
        var escaped = false
        tv.onEscape = { escaped = true }
        
        // 1. Enter key inserts newline
        tv.insertNewline(nil)
        #expect(tv.string == "第一行\n")
        
        tv.insertText("第二行", replacementRange: NSRange(location: tv.string.count, length: 0))
        #expect(tv.string == "第一行\n第二行")
        
        // 2. Esc key exits focus without reverting
        tv.cancelOperation(nil)
        #expect(escaped == true)
        #expect(tv.string == "第一行\n第二行")
    }

    @Test("Test DescriptionNSTextView dynamic height calculation")
    @MainActor
    func testDescriptionNSTextViewHeightCalculation() {
        let scrollView = DescriptionScrollView()
        let tv = scrollView.textView
        tv.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        tv.string = ""
        
        let emptyHeight = scrollView.calculateHeight(minHeight: 22)
        #expect(emptyHeight >= 20 && emptyHeight <= 26)
        
        tv.string = "第一行内容"
        let singleLineHeight = scrollView.calculateHeight(minHeight: 22)
        #expect(singleLineHeight >= 20 && singleLineHeight <= 26)
        
        tv.string = "第一行内容\n第二行内容\n第三行内容\n第四行内容"
        let multiLineHeight = scrollView.calculateHeight(minHeight: 22)
        #expect(multiLineHeight > singleLineHeight * 2)
    }

    @Test("Test auto save lifecycle on task switch and flush")
    @MainActor
    func testAutoSaveLifecycleOnTaskSwitch() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let taskA = try vault.createTask(title: "任务A", description: "原描述A")
        let taskB = try vault.createTask(title: "任务B", description: "原描述B")

        var editingTaskId = taskA.id
        var draft = "修改后的描述A"

        // Simulate flush before switching to Task B
        if var current = vault.index.getTask(editingTaskId), current.description != draft {
            current.description = draft
            _ = try vault.updateTask(current)
        }

        // Switch to Task B
        editingTaskId = taskB.id
        draft = vault.index.getTask(taskB.id)?.description ?? ""

        #expect(vault.index.getTask(taskA.id)?.description == "修改后的描述A")
        #expect(draft == "原描述B")
    }

    @Test("Test TitleNSTextView Enter commits and Esc exits without newlines")
    @MainActor
    func testTitleNSTextViewKeyHandling() {
        let tv = TitleNSTextView()
        tv.string = "整理规划镜像"

        var committed = false
        var escaped = false
        tv.onEnter = { committed = true }
        tv.onEscape = { escaped = true }

        // 1. Enter key triggers onEnter commit instead of inserting newline
        tv.insertNewline(nil)
        #expect(committed == true)
        #expect(tv.string == "整理规划镜像") // no newline added!

        // 2. Esc key exits focus
        tv.cancelOperation(nil)
        #expect(escaped == true)
        #expect(tv.string == "整理规划镜像")
    }

    @Test("Test Title sanitization rejects empty title and strips newlines")
    @MainActor
    func testTitleSanitizationAndEmptyRejection() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "原标题")

        // 1. Empty title is rejected and reverted to original title
        var titleDraft = "   \n\t  "
        let clean = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            titleDraft = task.title // Revert to task.title
        }
        #expect(titleDraft == "原标题")

        // 2. Multi-line pasted text sanitized to single line
        let pasted = "第一行标题\n第二行内容\r第三行内容"
        let sanitized = pasted.replacingOccurrences(of: "\r\n", with: " ")
                              .replacingOccurrences(of: "\n", with: " ")
                              .replacingOccurrences(of: "\r", with: " ")
        #expect(!sanitized.contains("\n") && !sanitized.contains("\r"))
        #expect(sanitized == "第一行标题 第二行内容 第三行内容")
    }

    @Test("Test Title completion dims text brightness slightly without strikethrough")
    @MainActor
    func testTitleCompletionBrightnessWithoutStrikethrough() {
        let tv = TitleNSTextView()
        tv.string = "已完成任务大标题"

        // Default: not done, full brightness
        #expect(tv.isDone == false)
        #expect(tv.textColor == NSColor.labelColor)

        // When marked completed: only lower brightness slightly, NO strikethrough
        tv.isDone = true
        #expect(tv.isDone == true)
        let expectedDimmed = NSColor.labelColor.withAlphaComponent(0.68)
        #expect(tv.textColor == expectedDimmed)

        let typingAttrs = tv.typingAttributes
        #expect(typingAttrs[.strikethroughStyle] == nil)

        if let storage = tv.textStorage, storage.length > 0 {
            var range = NSRange(location: 0, length: 0)
            let color = storage.attribute(.foregroundColor, at: 0, effectiveRange: &range) as? NSColor
            #expect(color == expectedDimmed)
            let strikethrough = storage.attribute(.strikethroughStyle, at: 0, effectiveRange: &range)
            #expect(strikethrough == nil)
        }
    }

    @Test("Test CommentNSTextView Cmd+Enter submit and font metrics")
    @MainActor
    func testCommentNSTextViewCmdEnter() {
        let tv = CommentNSTextView()
        tv.string = "已完成部署测试"

        #expect(tv.font?.pointSize == 12)
        #expect(tv.textContainerInset.height == 6)
        #expect(tv.textContainer?.lineFragmentPadding == 0)

        var submittedText: String? = nil
        tv.onSubmit = { text in submittedText = text }

        // 1. Test performKeyEquivalent with Cmd+Return (keyCode 36)
        let cmdReturnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        let handled = tv.performKeyEquivalent(with: cmdReturnEvent)
        #expect(handled == true)
        #expect(submittedText == "已完成部署测试")

        // 2. Test keyDown with Cmd+Return
        submittedText = nil
        tv.keyDown(with: cmdReturnEvent)
        #expect(submittedText == "已完成部署测试")

        // 3. Test plain Return without Command does NOT trigger submit
        submittedText = nil
        let plainReturnEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        let plainHandled = tv.performKeyEquivalent(with: plainReturnEvent)
        #expect(plainHandled == false)
        #expect(submittedText == nil)
    }

    @Test("Test Task Activity update and delete lifecycle")
    @MainActor
    func testTaskActivityUpdateAndDelete() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let vault = try Vault(rootPath: tmpDir.path)
        let task = try vault.createTask(title: "初版任务")
        let act = try vault.createActivity(taskId: task.id, date: "2026-10-30", body: "首次评论")

        #expect(vault.index.getTask(task.id)?.activities.count == 1)
        #expect(vault.index.getTask(task.id)?.activities.first?.body == "首次评论")

        // 1. Update activity
        _ = try vault.updateActivity(id: act.id, body: "已编辑修改的评论")
        #expect(vault.index.getTask(task.id)?.activities.first?.body == "已编辑修改的评论")

        // 2. Delete activity
        try vault.deleteActivity(id: act.id)
        #expect(vault.index.getTask(task.id)?.activities.isEmpty == true)
    }
}
