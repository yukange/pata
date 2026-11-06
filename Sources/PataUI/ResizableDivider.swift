import SwiftUI
import AppKit

struct ResizableDivider: View {
    @Binding var width: CGFloat
    let allowedWidth: ClosedRange<CGFloat>
    let defaultWidth: CGFloat
    let coordinateSpaceName: String
    let accentColor: Color
    let onCommit: () -> Void

    @State private var isHovered = false
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(
                isDragging || isHovered
                    ? accentColor.opacity(0.8)
                    : Color(nsColor: .separatorColor).opacity(0.6)
            )
            .frame(width: 1)
            // 用 overlay 撑命中区：改 padding 会占布局，分隔条会变成三条线
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
            }
            .onHover { hovering in
                isHovered = hovering
                (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .gesture(
                // 取父坐标系位移：.local 随手柄自身移动，位移反馈回自己会抖动
                DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpaceName))
                    .onChanged { value in
                        isDragging = true
                        let base = dragStartWidth ?? width
                        dragStartWidth = base
                        let target = base + (value.location.x - value.startLocation.x)
                        width = min(max(target, allowedWidth.lowerBound), allowedWidth.upperBound)
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragStartWidth = nil
                        onCommit()
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    width = defaultWidth
                    onCommit()
                }
            }
    }
}
