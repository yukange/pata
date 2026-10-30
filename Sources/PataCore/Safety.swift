import Foundation
import CryptoKit

public struct ConflictError: LocalizedError, Equatable {
    public let path: String
    public let expectedHash: String
    public let actualDiskHash: String
    public let expectedModTime: Date
    public let actualDiskModTime: Date

    public var errorDescription: String? {
        return "conflict at \(path): disk hash \(actualDiskHash) != baseline \(expectedHash) (mod_time disk: \(actualDiskModTime), baseline: \(expectedModTime))"
    }
}

public final class WriteTracker: @unchecked Sendable {
    private struct WriteRecord {
        let hash: String
        let timestamp: Date
    }

    private let lock = NSLock()
    private var recentWrites: [String: WriteRecord] = [:]
    private let retention: TimeInterval

    public init(retention: TimeInterval = 3.0) {
        self.retention = retention > 0 ? retention : 3.0
    }

    public func markInternalWrite(absPath: String, hash: String) {
        lock.lock()
        defer { lock.unlock() }
        cleanupLocked()
        recentWrites[absPath] = WriteRecord(hash: hash, timestamp: Date())
    }

    public func isInternalWrite(absPath: String, hash: String = "") -> Bool {
        lock.lock()
        defer { lock.unlock() }
        cleanupLocked()

        guard let rec = recentWrites[absPath] else {
            return false
        }

        if !hash.isEmpty && !rec.hash.isEmpty {
            if rec.hash == hash {
                recentWrites.removeValue(forKey: absPath)
                return true
            }
            return false
        }

        recentWrites.removeValue(forKey: absPath)
        return true
    }

    public func hasRecentWrites(inDirectory dirPath: String, window: TimeInterval = 2.0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        cleanupLocked()
        let now = Date()
        let prefix = dirPath.hasSuffix("/") ? dirPath : (dirPath + "/")
        for (path, record) in recentWrites {
            if path.hasPrefix(prefix) && now.timeIntervalSince(record.timestamp) <= window {
                return true
            }
        }
        return false
    }

    private func cleanupLocked() {
        let cutoff = Date().addingTimeInterval(-retention)
        for (p, rec) in recentWrites {
            if rec.timestamp < cutoff {
                recentWrites.removeValue(forKey: p)
            }
        }
    }
}

public struct Safety {
    /// Computes SHA-256 lowercase hex string.
    public static func computeContentHash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Reads baseline and raw data from disk.
    public static func readBaseline(absPath: String) throws -> (baseline: FileBaseline, data: Data) {
        let fileURL = URL(fileURLWithPath: absPath)
        let data = try Data(contentsOf: fileURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: absPath)
        let modTime = (attrs[.modificationDate] as? Date) ?? Date()
        let hash = computeContentHash(data)
        return (FileBaseline(path: absPath, hash: hash, modTime: modTime), data)
    }

    /// Atomically and safely writes data to targetPath with baseline conflict check.
    @discardableResult
    public static func safeWrite(
        targetPath: String,
        data: Data,
        baseline: FileBaseline? = nil,
        tracker: WriteTracker? = nil
    ) throws -> FileBaseline {
        let absURL = URL(fileURLWithPath: targetPath).standardized
        let absPath = absURL.path
        let dirURL = absURL.deletingLastPathComponent()
        let dirPath = dirURL.path

        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let newHash = computeContentHash(data)

        // Optimistic concurrency check
        if FileManager.default.fileExists(atPath: absPath) {
            let existingData = try Data(contentsOf: absURL)
            let existingAttrs = try? FileManager.default.attributesOfItem(atPath: absPath)
            let diskModTime = (existingAttrs?[.modificationDate] as? Date) ?? Date()
            let diskHash = computeContentHash(existingData)

            if let base = baseline {
                if base.hash != diskHash {
                    if newHash != diskHash {
                        throw ConflictError(
                            path: absPath,
                            expectedHash: base.hash,
                            actualDiskHash: diskHash,
                            expectedModTime: base.modTime,
                            actualDiskModTime: diskModTime
                        )
                    }
                }
            } else {
                // Baseline is nil (e.g. creating new entity)
                if newHash != diskHash {
                    throw ConflictError(
                        path: absPath,
                        expectedHash: "<new-file>",
                        actualDiskHash: diskHash,
                        expectedModTime: Date.distantPast,
                        actualDiskModTime: diskModTime
                    )
                }
            }
        } else if let base = baseline {
            // File deleted externally
            throw ConflictError(
                path: absPath,
                expectedHash: base.hash,
                actualDiskHash: "<deleted>",
                expectedModTime: base.modTime,
                actualDiskModTime: Date.distantPast
            )
        }

        // Write to temp file in same directory
        let tmpFileName = ".pata_tmp_\(UUID().uuidString)"
        let tmpURL = dirURL.appendingPathComponent(tmpFileName)
        let tmpPath = tmpURL.path

        var writeSuccess = false
        defer {
            if !writeSuccess {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        }

        // Open and write with fsync
        let fd = open(tmpPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        let writeCount = data.withUnsafeBytes { ptr in
            write(fd, ptr.baseAddress, data.count)
        }
        guard writeCount == data.count else {
            close(fd)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // Full fsync on macOS
        _ = fcntl(fd, F_FULLFSYNC)
        close(fd)

        // Register internal write before rename
        tracker?.markInternalWrite(absPath: absPath, hash: newHash)

        // Atomic replace
        guard rename(tmpPath, absPath) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        // Fsync parent directory
        let dirFd = open(dirPath, O_RDONLY)
        if dirFd >= 0 {
            _ = fcntl(dirFd, F_FULLFSYNC)
            close(dirFd)
        }

        writeSuccess = true

        let finalAttrs = try? FileManager.default.attributesOfItem(atPath: absPath)
        let finalModTime = (finalAttrs?[.modificationDate] as? Date) ?? Date()

        return FileBaseline(path: absPath, hash: newHash, modTime: finalModTime)
    }

    // MARK: - Path Resolution & Boundary Security

    public enum PathSafetyError: LocalizedError, Equatable {
        case emptyVaultRoot
        case emptyTargetPath
        case pathEscapesVault(String)
        case symlinkEscapesVault(String)

        public var errorDescription: String? {
            switch self {
            case .emptyVaultRoot: return "vault root cannot be empty"
            case .emptyTargetPath: return "target path cannot be empty"
            case .pathEscapesVault(let p): return "path escapes vault: \(p)"
            case .symlinkEscapesVault(let p): return "path escapes vault via symlink: \(p)"
            }
        }
    }

    /// Resolves a relative or absolute targetPath against vaultRoot.
    /// Verifies that the resulting path is strictly located within vaultRoot and does not escape via ".." or symlinks.
    /// Returns (absPath, relPath).
    public static func safeResolveVaultPath(vaultRoot: String, targetPath: String) throws -> (absPath: String, relPath: String) {
        let cleanRoot = vaultRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanRoot.isEmpty else {
            throw PathSafetyError.emptyVaultRoot
        }
        let cleanTarget = targetPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTarget.isEmpty else {
            throw PathSafetyError.emptyTargetPath
        }

        let absRootURL = URL(fileURLWithPath: cleanRoot).standardized
        let candidateURL: URL
        if (cleanTarget as NSString).isAbsolutePath {
            candidateURL = URL(fileURLWithPath: cleanTarget).standardized
        } else {
            candidateURL = absRootURL.appendingPathComponent(cleanTarget).standardized
        }

        let absRoot = absRootURL.path
        let candidate = candidateURL.path

        // Check path prefix to prevent ".." escape
        guard candidate == absRoot || candidate.hasPrefix(absRoot + "/") else {
            throw PathSafetyError.pathEscapesVault(targetPath)
        }

        // Relative path
        let relPath: String
        if candidate == absRoot {
            relPath = ""
        } else {
            relPath = String(candidate.dropFirst(absRoot.count + 1))
        }

        // Verify symlinks to prevent symlink escape
        let realRootURL = absRootURL.resolvingSymlinksInPath()
        let realRoot = realRootURL.path

        if FileManager.default.fileExists(atPath: candidate) {
            let evalTargetURL = candidateURL.resolvingSymlinksInPath()
            let evalTarget = evalTargetURL.path
            guard evalTarget == realRoot || evalTarget.hasPrefix(realRoot + "/") else {
                throw PathSafetyError.symlinkEscapesVault(targetPath)
            }
        } else {
            // Also check ancestor directories for symlink escape
            var current = candidateURL.deletingLastPathComponent()
            while current.path != "/" && current.path != "." {
                if FileManager.default.fileExists(atPath: current.path) {
                    let evalParent = current.resolvingSymlinksInPath().path
                    guard evalParent == realRoot || evalParent.hasPrefix(realRoot + "/") else {
                        throw PathSafetyError.symlinkEscapesVault(targetPath)
                    }
                    break
                }
                current = current.deletingLastPathComponent()
            }
        }

        return (candidate, relPath)
    }
}
