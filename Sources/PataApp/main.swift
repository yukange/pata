import SwiftUI
import AppKit
import PataUI
import PataCore

struct PataApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            AppShell()
                .frame(minWidth: 1000, minHeight: 650)
                .ignoresSafeArea()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .sidebar) {
                Button(AppState.shared.isSidebarVisible ? "隐藏侧边栏" : "显示侧边栏") {
                    AppState.shared.toggleSidebar()
                }
                .keyboardShortcut("s", modifiers: [.control, .command])

                Button("切换侧栏快捷键") {
                    AppState.shared.toggleSidebar()
                }
                .keyboardShortcut("b", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("关于 啪嗒 / Pata") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            .applicationName: "啪嗒 (Pata)",
                            .applicationVersion: "2.0.0",
                            .version: "2026.10"
                        ]
                    )
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("偏好设置...") {
                    AppState.shared.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

@MainActor
final class TitlebarCustomizer {
    static var isInstalled = false
    static let targetX: CGFloat = 18.0
    static let targetYOffsetFromTop: CGFloat = 12.0
    static let buttonSpacing: CGFloat = 8.0

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let dummy = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        guard let close = dummy.standardWindowButton(.closeButton),
              let titlebar = close.superview else { return }

        let titlebarClass: AnyClass = type(of: titlebar)
        let sel = #selector(NSView.layout)
        guard let origMethod = class_getInstanceMethod(titlebarClass, sel) else { return }
        let origImp = method_getImplementation(origMethod)
        typealias LayoutFunc = @convention(c) (AnyObject, Selector) -> Void
        let origLayout = unsafeBitCast(origImp, to: LayoutFunc.self)

        let newBlock: @convention(block) (AnyObject) -> Void = { obj in
            origLayout(obj, sel)
            guard let view = obj as? NSView, let win = view.window, !win.styleMask.contains(.fullScreen) else { return }
            guard let c = win.standardWindowButton(.closeButton),
                  let m = win.standardWindowButton(.miniaturizeButton),
                  let z = win.standardWindowButton(.zoomButton) else { return }

            let btnW: CGFloat = c.frame.width > 0 ? c.frame.width : 14.0
            let btnH: CGFloat = c.frame.height > 0 ? c.frame.height : 14.0
            let titlebarH = view.frame.height
            let y = titlebarH - targetYOffsetFromTop - btnH

            c.setFrameOrigin(NSPoint(x: targetX, y: y))
            m.setFrameOrigin(NSPoint(x: targetX + btnW + buttonSpacing, y: y))
            z.setFrameOrigin(NSPoint(x: targetX + (btnW + buttonSpacing) * 2, y: y))
        }

        method_setImplementation(origMethod, imp_implementationWithBlock(newBlock))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        TitlebarCustomizer.install()
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                for window in NSApp.windows {
                    Self.configureWindow(window)
                }
            }
        }
        DispatchQueue.main.async {
            for window in NSApp.windows {
                Self.configureWindow(window)
            }
        }
    }

    static func configureWindow(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.toolbar = nil
        window.layoutIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// Entrypoint
if let idx = CommandLine.arguments.firstIndex(of: "--snapshot"), idx + 1 < CommandLine.arguments.count {
    let outDir = CommandLine.arguments[idx + 1]
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let state = AppState.shared
    // Open DemoVault by default for 1:1 prototype fidelity
    let demoVaultPath = "/Users/wuyukang/code/github/pata-swift/DemoVault"
    state.openVault(path: demoVaultPath)
    print("Vault tasks count:", state.vault?.index.listTasks().count ?? -1)
    print("Vault parse errors:", state.vault?.index.listParseErrors() ?? [])
    let p = state.vault?.getDayPlan(date: "2026-10-11")
    print("Plan 2026-10-11 taskIds:", p?.taskIds ?? [])
    state.todayDateString = "2026-10-11"

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1440, height: 1050),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let hosting = NSHostingView(rootView: AppShell())
    window.contentView = hosting

    func capture(name: String, width: CGFloat = 1440, height: CGFloat = 940) {
        window.setContentSize(NSSize(width: width, height: height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: NSRect(x: 0, y: 0, width: width, height: height)) else {
            print("Failed bitmap rep for \(name)")
            return
        }
        hosting.cacheDisplay(in: NSRect(x: 0, y: 0, width: width, height: height), to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("Failed png for \(name)")
            return
        }
        let target = "\(outDir)/swift_\(name).png"
        try? png.write(to: URL(fileURLWithPath: target))
        print("Captured \(target), size: \(png.count) bytes")
    }

    // 1. Today View (1440 x 940)
    state.showSettings = false
    state.showSearch = false
    state.isSidebarVisible = true
    state.currentNav = .today
    state.isInspectorVisible = false
    state.selectedNoteId = nil
    capture(name: "today", width: 1440, height: 940)

    // 2. Tasks View (1440 x 940)
    state.currentNav = .tasks
    state.isInspectorVisible = false
    capture(name: "tasks", width: 1440, height: 940)

    // 2b. Tasks with Inspector (1440 x 940)
    state.selectedTaskId = "t-01m501"
    state.isInspectorVisible = true
    capture(name: "task_inspector", width: 1440, height: 940)
    state.isInspectorVisible = false

    // 3. Notes List View (1440 x 940)
    state.currentNav = .notes
    state.selectedNoteId = nil
    state.isInspectorVisible = false
    capture(name: "notes", width: 1440, height: 940)

    // 4. Note Editor View (1440 x 940)
    state.currentNav = .notes
    state.selectedNoteId = "n-01m501"
    capture(name: "note_editor", width: 1440, height: 940)

    // 5. Tag View (# 架构设计) (1440 x 940)
    state.currentNav = .tags
    state.selectedTag = "架构设计"
    capture(name: "tags", width: 1440, height: 940)

    // 6. Settings View (1440 x 940)
    state.showSettings = true
    capture(name: "settings", width: 1440, height: 940)

    // 7. Collapsed Sidebar View (1440 x 940)
    state.showSettings = false
    state.currentNav = .today
    state.isSidebarVisible = false
    capture(name: "collapsed_sidebar", width: 1440, height: 940)

    // 8. Search Overlay (1440 x 940)
    state.isSidebarVisible = true
    state.showSearch = true
    capture(name: "search", width: 1440, height: 940)
    state.showSearch = false

    // 9. Dark Mode (Today, Tasks, Notes, Settings)
    state.themePreference = "dark"
    state.currentNav = .today
    capture(name: "today_dark", width: 1440, height: 940)

    state.currentNav = .tasks
    capture(name: "tasks_dark", width: 1440, height: 940)

    state.currentNav = .notes
    state.selectedNoteId = "n-01m501"
    capture(name: "notes_dark", width: 1440, height: 940)

    state.showSettings = true
    capture(name: "settings_dark", width: 1440, height: 940)

    print("All screenshots generated successfully.")
    exit(0)
} else {
    PataApp.main()
}
