import Foundation
import PataCore

public struct UploadPolicy: Codable, Sendable {
    public var policy: String
    public var signature: String
    public var uploadDir: String
    public var uploadHost: String
    public var ossAccessKeyId: String
    public var xOssObjectAcl: String?
    public var xOssForbidOverwrite: String?

    enum CodingKeys: String, CodingKey {
        case policy
        case signature
        case uploadDir = "upload_dir"
        case uploadHost = "upload_host"
        case ossAccessKeyId = "oss_access_key_id"
        case xOssObjectAcl = "x_oss_object_acl"
        case xOssForbidOverwrite = "x_oss_forbid_overwrite"
    }
}

public struct DashScopeClient: Sendable {
    public let baseURL: String
    public let model: String

    public init(baseURL: String = ASRConstants.defaultBaseURL, model: String = ASRConstants.defaultModel) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.model = model
    }

    public func getUploadPolicy(apiKey: String) async throws -> UploadPolicy {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SchemaError.validationError(field: "apiKey", reason: "API Key 不能为空")
        }

        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model
        let urlStr = "\(baseURL)/api/v1/uploads?action=getPolicy&model=\(encodedModel)"
        guard let url = URL(string: urlStr) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard http.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "DashScope", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "获取上传策略失败: \(errorText)"])
        }

        struct PolicyResponse: Codable {
            let data: UploadPolicy
        }

        let decoded = try JSONDecoder().decode(PolicyResponse.self, from: data)
        return decoded.data
    }

    /// Uploads an audio file to the temporary OSS storage specified by policy using multipart form data.
    /// Returns the oss:// URI.
    public func uploadToOSS(policy: UploadPolicy, fileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(domain: "DashScope", code: 404, userInfo: [NSLocalizedDescriptionKey: "音频文件不存在: \(fileURL.path)"])
        }

        let attr = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attr[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            throw NSError(domain: "DashScope", code: 400, userInfo: [NSLocalizedDescriptionKey: "音频文件为空 (0 字节)"])
        }

        let maxLimit: Int64 = 1024 * 1024 * 1024 // 1GB
        if fileSize > maxLimit {
            throw NSError(domain: "DashScope", code: 400, userInfo: [NSLocalizedDescriptionKey: "音频文件大小超过允许的最大限制 (1GB)"])
        }

        let baseName = fileURL.lastPathComponent
        let cleanDir = policy.uploadDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let ossKey = cleanDir.isEmpty ? baseName : "\(cleanDir)/\(baseName)"

        guard let uploadURL = URL(string: policy.uploadHost) else {
            throw URLError(.badURL)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build multipart body into a temporary file to avoid large memory footprint
        let tempUploadFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oss_upload_\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tempUploadFile) }

        guard let stream = OutputStream(url: tempUploadFile, append: false) else {
            throw NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "创建上传临时文件失败"])
        }
        stream.open()
        defer { stream.close() }

        func writeString(_ str: String) throws {
            guard let data = str.data(using: .utf8) else { return }
            try data.withUnsafeBytes { buffer in
                guard let ptr = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
                var written = 0
                while written < buffer.count {
                    let result = stream.write(ptr + written, maxLength: buffer.count - written)
                    if result < 0 {
                        throw stream.streamError ?? NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "写入上传数据失败"])
                    }
                    written += result
                }
            }
        }

        func writeFormField(name: String, value: String) throws {
            try writeString("--\(boundary)\r\n")
            try writeString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            try writeString("\(value)\r\n")
        }

        try writeFormField(name: "OSSAccessKeyId", value: policy.ossAccessKeyId)
        try writeFormField(name: "policy", value: policy.policy)
        try writeFormField(name: "Signature", value: policy.signature)
        try writeFormField(name: "key", value: ossKey)
        try writeFormField(name: "x-oss-object-acl", value: policy.xOssObjectAcl ?? "private")
        try writeFormField(name: "x-oss-forbid-overwrite", value: policy.xOssForbidOverwrite ?? "true")
        try writeFormField(name: "success_action_status", value: "200")

        // File part (must be last for OSS)
        let mimeType = fileURL.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/mpeg"
        try writeString("--\(boundary)\r\n")
        try writeString("Content-Disposition: form-data; name=\"file\"; filename=\"\(baseName)\"\r\n")
        try writeString("Content-Type: \(mimeType)\r\n\r\n")

        // Stream audio file content
        guard let fileInputStream = InputStream(url: fileURL) else {
            throw NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "打开音频输入流失败"])
        }
        fileInputStream.open()
        defer { fileInputStream.close() }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while fileInputStream.hasBytesAvailable {
            let bytesRead = fileInputStream.read(&buffer, maxLength: buffer.count)
            if bytesRead < 0 {
                throw fileInputStream.streamError ?? NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "读取音频文件失败"])
            }
            if bytesRead == 0 { break }

            var written = 0
            while written < bytesRead {
                let res = stream.write(&buffer[written], maxLength: bytesRead - written)
                if res < 0 {
                    throw stream.streamError ?? NSError(domain: "DashScope", code: 500, userInfo: [NSLocalizedDescriptionKey: "写入上传流失败"])
                }
                written += res
            }
        }

        try writeString("\r\n--\(boundary)--\r\n")
        stream.close()

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: tempUploadFile)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        guard http.statusCode == 200 || http.statusCode == 204 else {
            let errorText = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "DashScope", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "上传至 OSS 失败 (\(http.statusCode)): \(errorText)"])
        }

        return "oss://\(ossKey)"
    }

    public func submitTask(ossURL: String, apiKey: String) async throws -> String {
        let urlStr = "\(baseURL)/api/v1/services/audio/asr/transcription"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("enable", forHTTPHeaderField: "X-DashScope-OssResourceResolve")

        let body: [String: Any] = [
            "model": model,
            "input": [
                "file_urls": [ossURL]
            ],
            "parameters": [
                "channel_id": [0],
                "diarization_enabled": true
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "DashScope", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "提交转写任务失败: \(msg)"])
        }

        struct SubmitResponse: Codable {
            struct Output: Codable {
                let taskId: String
                enum CodingKeys: String, CodingKey {
                    case taskId = "task_id"
                }
            }
            let output: Output
        }

        let decoded = try JSONDecoder().decode(SubmitResponse.self, from: data)
        return decoded.output.taskId
    }

    public func pollTaskStatus(taskId: String, apiKey: String) async throws -> (status: String, transcriptionURL: String?, errorMessage: String?) {
        let urlStr = "\(baseURL)/api/v1/tasks/\(taskId)"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw NSError(domain: "DashScope", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "查询任务失败: \(msg)"])
        }

        struct StatusResp: Codable {
            struct Output: Codable {
                let taskStatus: String
                let transcriptionUrl: String?
                let code: String?
                let message: String?
                struct Subtask: Codable {
                    let subtaskStatus: String
                    let transcriptionUrl: String?
                    let code: String?
                    let message: String?
                    enum CodingKeys: String, CodingKey {
                        case subtaskStatus = "subtask_status"
                        case transcriptionUrl = "transcription_url"
                        case code
                        case message
                    }
                }
                let results: [Subtask]?

                enum CodingKeys: String, CodingKey {
                    case taskStatus = "task_status"
                    case transcriptionUrl = "transcription_url"
                    case code
                    case message
                    case results
                }
            }
            let output: Output
            let code: String?
            let message: String?
        }

        let decoded = try JSONDecoder().decode(StatusResp.self, from: data)
        let tUrl = decoded.output.transcriptionUrl ?? decoded.output.results?.first?.transcriptionUrl
        let errMsg = decoded.output.results?.first?.message ?? decoded.output.message ?? decoded.message
        return (decoded.output.taskStatus, tUrl, errMsg)
    }

    public func fetchTranscriptionResult(url: URL) async throws -> [ASRSentence] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        struct DashScopeResult: Codable {
            struct TranscriptItem: Codable {
                struct SentenceItem: Codable {
                    let beginTime: Int
                    let endTime: Int
                    let text: String
                    let speakerId: Int?
                    enum CodingKeys: String, CodingKey {
                        case beginTime = "begin_time"
                        case endTime = "end_time"
                        case text
                        case speakerId = "speaker_id"
                    }
                }
                let sentences: [SentenceItem]?
            }
            let transcripts: [TranscriptItem]?
        }

        let decoded = try JSONDecoder().decode(DashScopeResult.self, from: data)
        var sentences: [ASRSentence] = []

        if let transcripts = decoded.transcripts {
            for t in transcripts {
                if let sList = t.sentences {
                    for s in sList {
                        sentences.append(ASRSentence(
                            beginTime: s.beginTime,
                            endTime: s.endTime,
                            text: s.text,
                            speakerId: s.speakerId ?? 1
                        ))
                    }
                }
            }
        }

        return sentences.sorted { $0.beginTime < $1.beginTime }
    }
}
