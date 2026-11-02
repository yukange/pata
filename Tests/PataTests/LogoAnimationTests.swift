import Testing
@testable import PataUI
import SwiftUI

@Suite("Logo Animation Tests")
struct LogoAnimationTests {
    @Test("Logo launch animation plays only once per app lifecycle")
    @MainActor
    func launchPlaysOnce() {
        let coordinator = LogoAnimationCoordinator.shared
        coordinator.resetLaunchStateForTesting()

        #expect(coordinator.trigger == .idle)

        // First launch
        coordinator.playLaunch()
        #expect(coordinator.trigger == .launch)

        // Reset to idle to test idempotency
        coordinator.stop()
        #expect(coordinator.trigger == .idle)

        // Subsequent launch attempt should be ignored
        coordinator.playLaunch()
        #expect(coordinator.trigger == .idle)
    }

    @Test("Interactive animation enforces cooldown window")
    @MainActor
    func interactiveCooldown() {
        let coordinator = LogoAnimationCoordinator.shared
        coordinator.resetLaunchStateForTesting()

        // First trigger
        coordinator.playInteractive()
        guard case let .interactive(id1) = coordinator.trigger else {
            Issue.record("Expected .interactive trigger")
            return
        }

        // Immediate consecutive trigger within 850ms should be rejected
        coordinator.playInteractive()
        guard case let .interactive(id2) = coordinator.trigger else {
            Issue.record("Expected .interactive trigger to remain unchanged")
            return
        }
        #expect(id1 == id2)

        coordinator.stop()
        #expect(coordinator.trigger == .idle)
    }

    @Test("Success animation merges consecutive events and generates unique triggers")
    @MainActor
    func successTriggersRestart() {
        let coordinator = LogoAnimationCoordinator.shared
        coordinator.resetLaunchStateForTesting()

        coordinator.playSuccess()
        guard case let .success(id1) = coordinator.trigger else {
            Issue.record("Expected .success trigger")
            return
        }

        // Second success trigger immediately afterwards restarts cleanly with a new ID
        coordinator.playSuccess()
        guard case let .success(id2) = coordinator.trigger else {
            Issue.record("Expected .success trigger")
            return
        }
        #expect(id1 != id2)

        coordinator.stop()
        #expect(coordinator.trigger == .idle)
    }

    @Test("PataLogoView instantiates with customizable size")
    @MainActor
    func logoViewSizes() {
        let viewDefault = PataLogoView()
        #expect(viewDefault.size == 24)

        let viewCustom = PataLogoView(size: 32)
        #expect(viewCustom.size == 32)
    }
}
