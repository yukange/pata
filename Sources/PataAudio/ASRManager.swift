import Foundation
import PataCore

@MainActor
public final class ASRManager: ObservableObject {
    public static let shared = ASRManager()

    @Published public private(set) var statuses: [String: ASRTaskStatus] = [:]

    private var activeTasks: [String: _Concurrency.Task<Void, Never>] = [:]
    private let client = DashScopeClient()

    public init() {}

    public func getStatus(for noteId: String) -> ASRTaskStatus {
        statuses[noteId] ?? ASRTaskStatus(
            noteId: noteId,
            state: .idle,
            stageMessage: ""
        )
    }

    /// Starts the asynchronous upload and transcription pipeline in the background.
    public func startTask(
        noteId: String,
        audioURL: URL,
        isRetranscribe: Bool = false,
        apiKey: String,
        onSave: @escaping @MainActor (String) throws -> Void,
        onCompletion: (@MainActor (Bool) -> Void)? = nil
    ) {
        // Prevent starting duplicate tasks for note if active
        if let current = statuses[noteId],
           current.state == .uploading || current.state == .transcribing || current.state == .writing || current.state == .pendingConfirmation {
            return
        }

        statuses[noteId] = ASRTaskStatus(
            noteId: noteId,
            state: .uploading,
            stageMessage: "正在准备音频..."
        )

        let task = _Concurrency.Task {
            do {
                // 1. Audio pre-processing & mono check
                let (targetAudioURL, warning, cleanup) = await AudioPreprocessor.prepareAudioForTranscription(url: audioURL)
                defer { cleanup() }
                try _Concurrency.Task.checkCancellation()

                await MainActor.run {
                    self.statuses[noteId] = ASRTaskStatus(
                        noteId: noteId,
                        state: .uploading,
                        stageMessage: "正在上传音频...",
                        warning: warning
                    )
                }

                // 2. DashScope Upload Policy
                let policy = try await client.getUploadPolicy(apiKey: apiKey)

                // 3. Upload to OSS
                let ossURL = try await client.uploadToOSS(policy: policy, fileURL: targetAudioURL)

                await MainActor.run {
                    self.statuses[noteId] = ASRTaskStatus(
                        noteId: noteId,
                        state: .transcribing,
                        stageMessage: "正在转写逐字稿...",
                        warning: warning
                    )
                }

                // 4. Submit Task
                let taskId = try await client.submitTask(ossURL: ossURL, apiKey: apiKey)

                // 5. Poll Task Status
                var transcriptionURL: String? = nil
                while true {
                    try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000) // 2s polling interval
                    if _Concurrency.Task.isCancelled { return }

                    let (status, tUrl, errMsg) = try await client.pollTaskStatus(taskId: taskId, apiKey: apiKey)
                    if status == "SUCCEEDED" {
                        transcriptionURL = tUrl
                        break
                    } else if status == "FAILED" {
                        throw NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: errMsg ?? "语音识别服务处理失败"])
                    }
                }

                guard let tUrlStr = transcriptionURL, let resultURL = URL(string: tUrlStr) else {
                    throw NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "未获取到逐字稿结果地址"])
                }

                await MainActor.run {
                    self.statuses[noteId] = ASRTaskStatus(
                        noteId: noteId,
                        state: .writing,
                        stageMessage: "正在获取与解析逐字稿...",
                        warning: warning
                    )
                }

                // 6. Fetch Result
                let sentences = try await client.fetchTranscriptionResult(url: resultURL)
                guard !sentences.isEmpty else {
                    throw NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "未识别到有效语音内容"])
                }

                let formattedMarkdown = ASRFormatter.formatTranscript(sentences: sentences)

                await MainActor.run {
                    if isRetranscribe {
                        self.statuses[noteId] = ASRTaskStatus(
                            noteId: noteId,
                            state: .pendingConfirmation,
                            stageMessage: "重新转写完成，等待确认替换",
                            warning: warning,
                            candidateTranscript: formattedMarkdown
                        )
                        onCompletion?(true)
                    } else {
                        do {
                            try onSave(formattedMarkdown)
                            self.statuses[noteId] = ASRTaskStatus(
                                noteId: noteId,
                                state: .completed,
                                stageMessage: "转写完成",
                                warning: warning
                            )
                            onCompletion?(true)
                        } catch {
                            self.statuses[noteId] = ASRTaskStatus(
                                noteId: noteId,
                                state: .failed,
                                stageMessage: "保存逐字稿失败",
                                error: error.localizedDescription,
                                warning: warning
                            )
                            onCompletion?(false)
                        }
                    }
                }
            } catch {
                if !_Concurrency.Task.isCancelled {
                    await MainActor.run {
                        self.statuses[noteId] = ASRTaskStatus(
                            noteId: noteId,
                            state: .failed,
                            stageMessage: "转写失败",
                            error: error.localizedDescription
                        )
                        onCompletion?(false)
                    }
                }
            }
        }

        activeTasks[noteId] = task
    }

    /// Confirms replacement of current note transcript with candidate transcript.
    public func confirmReplace(noteId: String, onSave: @escaping @MainActor (String) throws -> Void) {
        guard let current = statuses[noteId],
              current.state == .pendingConfirmation,
              let candidate = current.candidateTranscript else {
            return
        }

        do {
            try onSave(candidate)
            statuses[noteId] = ASRTaskStatus(
                noteId: noteId,
                state: .completed,
                stageMessage: "逐字稿已更新",
                warning: current.warning
            )
        } catch {
            statuses[noteId] = ASRTaskStatus(
                noteId: noteId,
                state: .failed,
                stageMessage: "替换逐字稿失败",
                error: error.localizedDescription,
                warning: current.warning
            )
        }
    }

    /// Discards candidate transcript and keeps existing note content.
    public func discardCandidate(noteId: String) {
        if let current = statuses[noteId] {
            statuses[noteId] = ASRTaskStatus(
                noteId: noteId,
                state: .idle,
                stageMessage: "已保留原有逐字稿",
                warning: current.warning
            )
        }
    }

    /// Cancels active task and resets state for note.
    public func cancelTask(noteId: String) {
        activeTasks[noteId]?.cancel()
        activeTasks.removeValue(forKey: noteId)
        statuses.removeValue(forKey: noteId)
    }
}
