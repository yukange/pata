import Foundation
import Security

public protocol KeychainStore: Sendable {
    func get(service: String, account: String) throws -> String?
    func set(service: String, account: String, secret: String) throws
    func delete(service: String, account: String) throws
}

public enum KeychainError: LocalizedError, Equatable {
    case emptySecret
    case readFailed(OSStatus)
    case writeFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .emptySecret:
            return "Secret cannot be empty"
        case .readFailed(let status):
            return "Keychain read failed (OSStatus \(status))"
        case .writeFailed(let status):
            return "Keychain write failed (OSStatus \(status))"
        case .deleteFailed(let status):
            return "Keychain delete failed (OSStatus \(status))"
        }
    }
}

public final class DefaultKeychainStore: KeychainStore, @unchecked Sendable {
    public static let shared = DefaultKeychainStore()

    public init() {}

    public func get(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainError.readFailed(status)
        }
        guard let data = item as? Data, let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    public func set(service: String, account: String, secret: String) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw KeychainError.emptySecret
        }

        let data = Data(trimmed.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Delete any existing item first so that stale ACLs bound to previous CDHashes are cleared.
        SecItemDelete(query as CFDictionary)

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        #if os(macOS)
        var access: SecAccess?
        // Passing nil for trustedlist indicates that any application (e.g. newly rebuilt binaries
        // with different ad-hoc CDHashes) is allowed access without prompting the user for password each time.
        if SecAccessCreate(service as CFString, nil, &access) == errSecSuccess, let access = access {
            addQuery[kSecAttrAccess as String] = access
        }
        #endif

        var addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        #if os(macOS)
        if addStatus != errSecSuccess && addQuery[kSecAttrAccess as String] != nil {
            // Fallback without kSecAttrAccess if environment restricts SecAccess
            addQuery.removeValue(forKey: kSecAttrAccess as String)
            addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        }
        #endif

        guard addStatus == errSecSuccess else {
            throw KeychainError.writeFailed(addStatus)
        }
    }

    public func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }
        throw KeychainError.deleteFailed(status)
    }
}
