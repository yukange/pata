import AppKit
import Foundation
import MarkdownEngine
import PataCore

/// In-memory image cache for note images to avoid redundant disk I/O and network downloads.
public final class PataImageCache: @unchecked Sendable {
    public static let shared = PataImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500
        cache.totalCostLimit = 120 * 1024 * 1024 // ~120 MB
    }

    public func image(forKey key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    public func setImage(_ image: NSImage, forKey key: String, cost: Int = 0) {
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    public func remove(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }

    public func removeAll() {
        cache.removeAllObjects()
    }
}

/// Native image provider for Pata Markdown Note Editor, conforming to `MarkdownEngine.EmbeddedImageProvider`.
/// Seamlessly resolves:
/// 1. Markdown relative paths (e.g. `../files/pic.png`, `files/pic.png`, `./pic.png`) relative to Note or Vault.
/// 2. Vault-wide `files/` filename matches (e.g. `pic.png` or `![[pic.png]]`).
/// 3. Local absolute file paths and `file://` URLs.
/// 4. Percent-encoded paths (e.g. `%20`, unicode characters).
/// 5. Base64 Data URIs (`data:image/...;base64,...`).
/// 6. Remote HTTP / HTTPS URLs with memory caching and async background loading.
public final class PataEmbeddedImageProvider: EmbeddedImageProvider, @unchecked Sendable {
    public let vaultPath: String?
    public let noteFilePath: String?
    public let noteWidth: CGFloat
    public var onImageLoaded: (() -> Void)?

    private let lock = NSLock()
    private var version: Int = 0
    private var pendingDownloads = Set<URL>()

    public init(
        vaultPath: String? = nil,
        noteFilePath: String? = nil,
        noteWidth: CGFloat = 0,
        onImageLoaded: (() -> Void)? = nil
    ) {
        self.vaultPath = vaultPath
        self.noteFilePath = noteFilePath
        self.noteWidth = noteWidth
        self.onImageLoaded = onImageLoaded
    }

    public func fingerprint() -> AnyHashable {
        lock.lock()
        defer { lock.unlock() }
        return "\(vaultPath ?? ""):\(noteFilePath ?? ""):\(Int(noteWidth)):\(version)"
    }

    public func image(for reference: EmbeddedImageRequest) -> NSImage? {
        var raw = reference.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        // 1. Strip optional markdown title: e.g. `image.png "title"`
        if let spaceIdx = raw.firstIndex(where: { $0.isWhitespace }),
           raw.contains("\"") || raw.contains("'") {
            raw = String(raw[..<spaceIdx])
        }

        // 2. Strip fragment/query for file paths (preserve data URIs)
        if !raw.hasPrefix("data:") {
            if let hashIdx = raw.firstIndex(of: "#") {
                raw = String(raw[..<hashIdx])
            }
            if let qIdx = raw.firstIndex(of: "?") {
                raw = String(raw[..<qIdx])
            }
        }

        let cacheKey = raw
        if let cached = PataImageCache.shared.image(forKey: cacheKey) {
            return cached
        }

        // 3. Base64 Data URI
        if raw.hasPrefix("data:image/") {
            if let commaIdx = raw.firstIndex(of: ",") {
                let meta = String(raw[..<commaIdx])
                let base64Data = String(raw[raw.index(after: commaIdx)...])
                if meta.contains(";base64"),
                   let data = Data(base64Encoded: base64Data, options: [.ignoreUnknownCharacters]),
                   let img = NSImage(data: data) {
                    ensureValidImageSize(img)
                    PataImageCache.shared.setImage(img, forKey: cacheKey)
                    return img
                }
            }
            return nil
        }

        // 4. Remote HTTP/HTTPS Image
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            if let url = URL(string: raw) {
                downloadAsync(url: url, cacheKey: cacheKey)
            }
            return nil
        }

        // 5. Local File Paths
        var localPath = raw
        if localPath.hasPrefix("file://") {
            if let url = URL(string: localPath) {
                localPath = url.path
            }
        }
        let decodedPath = localPath.removingPercentEncoding ?? localPath

        var candidates: [String] = []

        // a. Absolute path
        if decodedPath.hasPrefix("/") {
            candidates.append(decodedPath)
        }

        // b. Relative to Note directory
        if let noteFile = noteFilePath, !noteFile.isEmpty {
            let noteDir = (noteFile as NSString).deletingLastPathComponent
            let combined = (noteDir as NSString).appendingPathComponent(decodedPath)
            candidates.append(URL(fileURLWithPath: combined).standardized.path)
        }

        // c. Relative to Vault root or files/ directory
        if let vault = vaultPath, !vault.isEmpty {
            let direct = (vault as NSString).appendingPathComponent(decodedPath)
            candidates.append(URL(fileURLWithPath: direct).standardized.path)

            let inFiles = ((vault as NSString).appendingPathComponent("files") as NSString).appendingPathComponent(decodedPath)
            candidates.append(URL(fileURLWithPath: inFiles).standardized.path)

            // Plain filename lookup inside files/ (e.g. for `![[pic.png]]` or `![alt](pic.png)`)
            let lastComp = (decodedPath as NSString).lastPathComponent
            let fileOnly = ((vault as NSString).appendingPathComponent("files") as NSString).appendingPathComponent(lastComp)
            candidates.append(URL(fileURLWithPath: fileOnly).standardized.path)
        }

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                if let img = NSImage(contentsOfFile: path) ?? (try? Data(contentsOf: URL(fileURLWithPath: path))).flatMap({ NSImage(data: $0) }) {
                    ensureValidImageSize(img)
                    PataImageCache.shared.setImage(img, forKey: cacheKey)
                    return img
                }
            }
        }

        return nil
    }

    private func ensureValidImageSize(_ image: NSImage) {
        if image.size.width <= 0 || image.size.height <= 0 {
            if let rep = image.representations.first {
                image.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
    }

    private func downloadAsync(url: URL, cacheKey: String) {
        lock.lock()
        if pendingDownloads.contains(url) {
            lock.unlock()
            return
        }
        pendingDownloads.insert(url)
        lock.unlock()

        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self else { return }
            defer {
                self.lock.lock()
                self.pendingDownloads.remove(url)
                self.lock.unlock()
            }
            guard let data = data, let img = NSImage(data: data) else { return }
            self.ensureValidImageSize(img)
            PataImageCache.shared.setImage(img, forKey: cacheKey)

            self.lock.lock()
            self.version += 1
            self.lock.unlock()

            DispatchQueue.main.async {
                self.onImageLoaded?()
            }
        }.resume()
    }
}

/// Helper methods for handling pasteboard images in Note editor.
public enum PataImageHelper {
    public static func canPasteImage(from pasteboard: NSPasteboard) -> Bool {
        PasteboardImageReader.canPasteImage(from: pasteboard)
    }

    public static func handlePasteImage(
        from pasteboard: NSPasteboard,
        vaultPath: String,
        noteFilePath: String?
    ) -> String? {
        guard PasteboardImageReader.canPasteImage(from: pasteboard) else { return nil }

        let filesDir = (vaultPath as NSString).appendingPathComponent("files")
        try? FileManager.default.createDirectory(atPath: filesDir, withIntermediateDirectories: true)

        let noteDir = noteFilePath.map { ($0 as NSString).deletingLastPathComponent }
            ?? (vaultPath as NSString).appendingPathComponent("notes")

        // 1. File URL on pasteboard
        if let fileURL = PasteboardImageReader.imageFileURL(from: pasteboard) {
            let originalName = fileURL.lastPathComponent
            let baseExt = (originalName as NSString).pathExtension
            let baseStem = (originalName as NSString).deletingPathExtension
            var candidateName = originalName
            var candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
            var counter = 1
            while FileManager.default.fileExists(atPath: candidatePath) {
                candidateName = "\(baseStem)_\(counter).\(baseExt)"
                candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
                counter += 1
            }
            do {
                try FileManager.default.copyItem(at: fileURL, to: URL(fileURLWithPath: candidatePath))
                let markdownPath = Links.relativePath(from: noteDir, to: candidatePath)
                return "![](\(markdownPath))\n"
            } catch {
                return nil
            }
        }

        // 2. Raw image data on pasteboard
        if let data = PasteboardImageReader.imageData(from: pasteboard) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let timeStr = formatter.string(from: Date())
            var candidateName = "image_\(timeStr).png"
            var candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
            var counter = 1
            while FileManager.default.fileExists(atPath: candidatePath) {
                candidateName = "image_\(timeStr)_\(counter).png"
                candidatePath = (filesDir as NSString).appendingPathComponent(candidateName)
                counter += 1
            }
            do {
                try data.write(to: URL(fileURLWithPath: candidatePath))
                let markdownPath = Links.relativePath(from: noteDir, to: candidatePath)
                return "![](\(markdownPath))\n"
            } catch {
                return nil
            }
        }

        return nil
    }
}

