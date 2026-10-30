import Foundation
import PataCore

public struct UploadPolicy: Codable, Sendable {
    public var policy: String
    public var signature: String
    public var uploadDir: String
    public var uploadHost: String
    public var ossAccessKeyId: String

    enum CodingKeys: String, CodingKey {
        case policy
        case signature
        case uploadDir = "upload_dir"
        case uploadHost = "upload_host"
        case ossAccessKeyId = "oss_access_key_id"
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

    public func pollTaskStatus(taskId: String, apiKey: String) async throws -> (status: String, transcriptionURL: String?) {
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
                struct Subtask: Codable {
                    let subtaskStatus: String
                    let transcriptionUrl: String?
                    enum CodingKeys: String, CodingKey {
                        case subtaskStatus = "subtask_status"
                        case transcriptionUrl = "transcription_url"
                    }
                }
                let results: [Subtask]?

                enum CodingKeys: String, CodingKey {
                    case taskStatus = "task_status"
                    case transcriptionUrl = "transcription_url"
                    case results
                }
            }
            let output: Output
        }

        let decoded = try JSONDecoder().decode(StatusResp.self, from: data)
        let tUrl = decoded.output.transcriptionUrl ?? decoded.output.results?.first?.transcriptionUrl
        return (decoded.output.taskStatus, tUrl)
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
