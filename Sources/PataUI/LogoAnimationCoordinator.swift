import SwiftUI

public enum LogoAnimationTrigger: Equatable {
    case idle
    case launch
    case success(UUID)
    case interactive(UUID)
}

@MainActor
public final class LogoAnimationCoordinator: ObservableObject {
    public static let shared = LogoAnimationCoordinator()

    @Published public private(set) var trigger: LogoAnimationTrigger = .idle

    private var hasPlayedLaunch = false
    private var lastTriggerTime: Date = .distantPast
    private let cooldownSeconds: TimeInterval = 0.85
    private var resetTask: Task<Void, Never>?

    public init() {}

    /// 应用冷启动就绪时触发（全生命周期仅播放一次）
    public func playLaunch() {
        guard !hasPlayedLaunch else { return }
        hasPlayedLaunch = true

        trigger = .launch
        scheduleReset(after: 0.75)
    }

    /// 业务成功保存时触发（Today/Task 独立新增/状态完成；连续保存时重置重播，不排队）
    public func playSuccess() {
        trigger = .success(UUID())
        scheduleReset(after: 0.85)
    }

    /// 用户点击或悬停 Logo 时触发（具备 850ms 防抖冷却，播放中不打断）
    public func playInteractive() {
        if case .launch = trigger { return }
        if case .interactive = trigger { return }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) >= cooldownSeconds else { return }
        lastTriggerTime = now

        trigger = .interactive(UUID())
        scheduleReset(after: 0.92)
    }

    /// 立即停止并恢复静态基线
    public func stop() {
        resetTask?.cancel()
        resetTask = nil
        trigger = .idle
    }

    /// 用于测试或重置冷启动状态
    public func resetLaunchStateForTesting() {
        hasPlayedLaunch = false
        lastTriggerTime = .distantPast
        stop()
    }

    private func scheduleReset(after seconds: Double) {
        resetTask?.cancel()
        resetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                self?.trigger = .idle
            }
        }
    }
}
