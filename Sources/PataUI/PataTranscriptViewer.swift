import SwiftUI
import PataEditor

public struct TranscriptBlock: Identifiable, Sendable {
    public let id: String
    public let timestampStr: String?
    public let timestampMs: Int?
    public let speaker: String?
    public let text: String

    public init(id: String, timestampStr: String?, timestampMs: Int?, speaker: String?, text: String) {
        self.id = id
        self.timestampStr = timestampStr
        self.timestampMs = timestampMs
        self.speaker = speaker
        self.text = text
    }
}

public enum TranscriptParser: Sendable {
    public static func parse(_ body: String) -> [TranscriptBlock] {
        guard !body.isEmpty else { return [] }
        let lines = body.components(separatedBy: "\n")
        var blocks: [TranscriptBlock] = []
        var currentTsStr: String?
        var currentMs: Int?
        var currentSpeaker: String?
        var currentLines: [String] = []

        func flush() {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if currentTsStr != nil || !text.isEmpty {
                blocks.append(TranscriptBlock(
                    id: "tb-\(blocks.count)-\(currentMs ?? 0)",
                    timestampStr: currentTsStr,
                    timestampMs: currentMs,
                    speaker: currentSpeaker,
                    text: text
                ))
            }
            currentTsStr = nil
            currentMs = nil
            currentSpeaker = nil
            currentLines.removeAll(keepingCapacity: true)
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Recognize [00:00:00.160](#t=00:00:00.160) Speaker or [00:00:00.160] Speaker
            if trimmed.hasPrefix("[") && (trimmed.contains("](#t=") || trimmed.contains("] ")) {
                if let closeBracket = trimmed.firstIndex(of: "]") {
                    let tsCandidate = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeBracket])
                    if let ms = PataTimestampParser.parseMilliseconds(tsCandidate) {
                        flush()
                        currentTsStr = tsCandidate
                        currentMs = ms
                        if let anchorEnd = trimmed.range(of: ")")?.upperBound {
                            let spk = String(trimmed[anchorEnd...]).trimmingCharacters(in: .whitespaces)
                            currentSpeaker = spk.isEmpty ? nil : spk
                        } else {
                            let spk = String(trimmed[trimmed.index(after: closeBracket)...]).trimmingCharacters(in: .whitespaces)
                            currentSpeaker = spk.isEmpty ? nil : spk
                        }
                        continue
                    }
                }
            }
            currentLines.append(line)
        }
        flush()
        return blocks
    }

    public static func findBlockIndex(in blocks: [TranscriptBlock], atTime targetMs: Int) -> Int? {
        guard !blocks.isEmpty else { return nil }
        var bestIdx: Int? = nil
        var bestMs = -1
        var firstTimedIdx: Int? = nil

        for (idx, b) in blocks.enumerated() {
            guard let ms = b.timestampMs else { continue }
            if firstTimedIdx == nil {
                firstTimedIdx = idx
            }
            if ms <= targetMs {
                if bestMs == -1 || ms >= bestMs {
                    bestMs = ms
                    bestIdx = idx
                }
            }
        }
        return bestIdx ?? firstTimedIdx
    }
}

/// Lightweight, instant-rendering viewer for audio transcript notes.
/// Eliminates heavy TextKit 2 document-wide ensureLayout on open, rendering in < 5ms.
public struct PataTranscriptViewer: View {
    let bodyText: String
    let accentColor: Color
    @Binding var scrollToMs: Int?
    let onSeekAudio: (Int) -> Void

    @State private var blocks: [TranscriptBlock] = []
    @State private var highlightedId: String? = nil
    @State private var clearHighlightTask: DispatchWorkItem? = nil

    public init(
        body: String,
        accentColor: Color,
        scrollToMs: Binding<Int?>,
        onSeekAudio: @escaping (Int) -> Void
    ) {
        self.bodyText = body
        self.accentColor = accentColor
        self._scrollToMs = scrollToMs
        self.onSeekAudio = onSeekAudio
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(blocks) { block in
                        transcriptRow(block)
                            .id(block.id)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .textSelection(.enabled)
            .onAppear {
                self.blocks = TranscriptParser.parse(bodyText)
            }
            .onChange(of: bodyText) { _, newBody in
                self.blocks = TranscriptParser.parse(newBody)
            }
            .onChange(of: scrollToMs) { _, newMs in
                guard let targetMs = newMs else { return }
                if let idx = TranscriptParser.findBlockIndex(in: blocks, atTime: targetMs) {
                    let targetBlock = blocks[idx]
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(targetBlock.id, anchor: .center)
                    }
                    highlightedId = targetBlock.id
                    clearHighlightTask?.cancel()
                    let work = DispatchWorkItem {
                        highlightedId = nil
                    }
                    clearHighlightTask = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
                }
                scrollToMs = nil
            }
        }
    }

    @ViewBuilder
    private func transcriptRow(_ block: TranscriptBlock) -> some View {
        let isHighlighted = highlightedId == block.id

        VStack(alignment: .leading, spacing: 6) {
            if block.timestampStr != nil || block.speaker != nil {
                HStack(spacing: 8) {
                    if let tsStr = block.timestampStr, let tsMs = block.timestampMs {
                        Button(action: {
                            onSeekAudio(tsMs)
                        }) {
                            Text("[\(tsStr)]")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(accentColor.opacity(0.12))
                                )
                                .foregroundColor(accentColor)
                        }
                        .buttonStyle(.plain)
                        .help("点击跳转到该时间戳播放")
                    }

                    if let speaker = block.speaker {
                        Text(speaker)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.85))
                    }

                    Spacer()
                }
            }

            Text(block.text)
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}
