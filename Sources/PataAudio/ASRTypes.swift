import Foundation

public struct ASRConstants {
    public static let defaultProvider = "阿里云百炼"
    public static let defaultModel = "qwen-audio-3.1-asr-flash-filetrans"
    public static let defaultRegion = "华北2（北京）"
    public static let defaultBaseURL = "https://dashscope.aliyuncs.com"

    public static let keychainService = "pata.asr"
    public static let keychainAccount = "aliyun_bailian_api_key"
}

public struct ASRSentence: Codable, Sendable, Equatable {
    public var beginTime: Int // ms
    public var endTime: Int   // ms
    public var text: String
    public var speakerId: Int

    public init(beginTime: Int, endTime: Int, text: String, speakerId: Int) {
        self.beginTime = beginTime
        self.endTime = endTime
        self.text = text
        self.speakerId = speakerId
    }

    enum CodingKeys: String, CodingKey {
        case beginTime = "begin_time"
        case endTime = "end_time"
        case text
        case speakerId = "speaker_id"
    }
}

public enum ASRTaskState: String, Codable, Sendable {
    case idle = "idle"
    case uploading = "uploading"
    case transcribing = "transcribing"
    case writing = "writing"
    case pendingConfirmation = "pending_confirmation"
    case completed = "completed"
    case failed = "failed"
}

public struct ASRTaskStatus: Codable, Sendable {
    public var noteId: String
    public var state: ASRTaskState
    public var stageMessage: String
    public var error: String?
    public var warning: String?
    public var candidateTranscript: String?
    public var updatedAt: Date

    public init(
        noteId: String,
        state: ASRTaskState,
        stageMessage: String,
        error: String? = nil,
        warning: String? = nil,
        candidateTranscript: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.noteId = noteId
        self.state = state
        self.stageMessage = stageMessage
        self.error = error
        self.warning = warning
        self.candidateTranscript = candidateTranscript
        self.updatedAt = updatedAt
    }
}

public struct ASRFormatter {
    /// Formats milliseconds to HH:mm:ss.SSS.
    public static func formatMilliseconds(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let msec = ms % 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, msec)
    }

    /// Parses timestamp string (e.g. "00:01:05.230" or "#t=00:01:05.230") to milliseconds.
    public static func parseMilliseconds(_ timeStr: String) -> Int? {
        var str = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#t=") {
            str = String(str.dropFirst(3))
        }
        let parts = str.components(separatedBy: ":")
        guard parts.count == 3 else { return nil }
        guard let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }

        let secParts = parts[2].components(separatedBy: ".")
        guard let seconds = Int(secParts[0]) else { return nil }
        let ms: Int
        if secParts.count > 1 {
            let frac = secParts[1].prefix(3)
            ms = (Int(frac) ?? 0) * (frac.count == 1 ? 100 : (frac.count == 2 ? 10 : 1))
        } else {
            ms = 0
        }

        return (hours * 3600 + minutes * 60 + seconds) * 1000 + ms
    }

    /// Formats recognized sentences into standard read-only transcript Markdown.
    public static func formatTranscript(sentences: [ASRSentence]) -> String {
        var blocks: [String] = []
        for s in sentences {
            let ts = formatMilliseconds(s.beginTime)
            let speakerName = s.speakerId > 0 ? "说话人 \(s.speakerId)" : "说话人"
            let header = "[\(ts)](#t=\(ts)) \(speakerName)"
            blocks.append("\(header)\n\n\(s.text)")
        }
        return blocks.joined(separator: "\n\n")
    }
}
