import AppKit
import SwiftUI

/// 只在启动或点击 Dock 时短暂绘制图标，结束后交还系统。
@MainActor
final class DockIconAnimator {
    private struct Motion {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: CGFloat = 0
    }

    private final class IconView: NSView {
        let image: NSImage
        var motion = Motion()

        init(image: NSImage, size: NSSize) {
            self.image = image
            super.init(frame: NSRect(origin: .zero, size: size))
            autoresizingMask = [.width, .height]
        }

        required init?(coder: NSCoder) { nil }

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.clear(bounds)
            context.saveGState()
            let anchor = CGPoint(x: bounds.midX, y: bounds.height * 0.22)
            context.translateBy(x: anchor.x, y: anchor.y)
            context.rotate(by: motion.rotation * .pi / 180)
            context.scaleBy(x: motion.scaleX, y: motion.scaleY)
            context.translateBy(x: -anchor.x, y: -anchor.y)
            image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
            context.restoreGState()
        }
    }

    private let timeline = KeyframeTimeline(initialValue: Motion()) {
        KeyframeTrack(\.scaleX) {
            CubicKeyframe(1.03, duration: 0.10)
            CubicKeyframe(0.98, duration: 0.18)
            CubicKeyframe(1.01, duration: 0.16)
            CubicKeyframe(1.00, duration: 0.22)
        }
        KeyframeTrack(\.scaleY) {
            CubicKeyframe(0.91, duration: 0.10)
            CubicKeyframe(1.04, duration: 0.18)
            CubicKeyframe(0.98, duration: 0.16)
            CubicKeyframe(1.00, duration: 0.22)
        }
        KeyframeTrack(\.rotation) {
            CubicKeyframe(-2.0, duration: 0.10)
            CubicKeyframe(1.5, duration: 0.18)
            CubicKeyframe(-0.5, duration: 0.16)
            CubicKeyframe(0.0, duration: 0.22)
        }
    }

    private var timer: Timer?
    private var tile: NSDockTile?
    private var previousContentView: NSView?

    func play() {
        guard timer == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let image = NSApplication.shared.applicationIconImage else { return }
        let tile = NSApplication.shared.dockTile
        guard tile.size.width > 0, tile.size.height > 0 else { return }

        previousContentView = tile.contentView
        self.tile = tile
        let view = IconView(image: image, size: tile.size)
        tile.contentView = view
        tile.display()
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak view] timer in
            guard let self else { timer.invalidate(); return }
            MainActor.assumeIsolated {
                guard let view else { self.stop(); return }
                let time = ProcessInfo.processInfo.systemUptime - start
                guard time < self.timeline.duration,
                      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { self.stop(); return }
                view.motion = self.timeline.value(time: time)
                self.tile?.display()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let tile {
            tile.contentView = previousContentView
            tile.display()
        }
        tile = nil
        previousContentView = nil
    }
}
