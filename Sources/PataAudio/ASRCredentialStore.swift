import Foundation
import Darwin

public struct ASRCredentialStore: Sendable {
    public static let shared = ASRCredentialStore()
    public let fileURL: URL

    private struct Credential: Codable {
        let apiKey: String
    }

    public enum StoreError: LocalizedError {
        case emptyKey
        case invalidFile

        public var errorDescription: String? {
            switch self {
            case .emptyKey: return "API Key 不能为空"
            case .invalidFile: return "ASR 密钥文件格式无效，请在设置中重新保存 API Key"
            }
        }
    }

    public init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pata/asr.json")) {
        self.fileURL = fileURL
    }

    public func load() throws -> String? {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
        guard let credential = try? JSONDecoder().decode(Credential.self, from: data) else {
            throw StoreError.invalidFile
        }
        let key = credential.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StoreError.emptyKey }
        let manager = FileManager.default
        let directory = fileURL.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(Credential(apiKey: key))
        let temporary = directory.appendingPathComponent(".asr-\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        guard manager.createFile(atPath: temporary.path, contents: data,
                                 attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Same-directory rename atomically replaces the file only after a complete write.
        guard rename(temporary.path, fileURL.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}
