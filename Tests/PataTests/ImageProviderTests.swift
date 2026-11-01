import Testing
import Foundation
import AppKit
import MarkdownEngine
import PataCore
import PataEditor

@Suite("Note Image Provider & Linking Tests")
struct ImageProviderTests {

    @Test("Relative path computation across directories")
    func relativePathComputation() {
        // 1. From notes/ to files/
        let r1 = Links.relativePath(from: "/vault/notes", to: "/vault/files/photo.png")
        #expect(r1 == "../files/photo.png")

        // 2. From notes/sub/ to files/
        let r2 = Links.relativePath(from: "/vault/notes/sub", to: "/vault/files/photo.png")
        #expect(r2 == "../../files/photo.png")

        // 3. Same directory
        let r3 = Links.relativePath(from: "/vault/notes", to: "/vault/notes/photo.png")
        #expect(r3 == "photo.png")

        // 4. Down to subfolder
        let r4 = Links.relativePath(from: "/vault", to: "/vault/files/photo.png")
        #expect(r4 == "files/photo.png")
    }

    @Test("Vault import raw image data and auto-deduplication")
    func vaultImportImageData() throws {
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_img_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let vault = try Vault(rootPath: tempDir)

        // 1x1 transparent PNG data
        let samplePNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

        let relPath1 = try vault.importFileData(samplePNGData, filename: "screenshot.png")
        #expect(relPath1 == "files/screenshot.png")

        let fullPath1 = (tempDir as NSString).appendingPathComponent("files/screenshot.png")
        #expect(FileManager.default.fileExists(atPath: fullPath1))

        // Importing again with same filename should not overwrite, but create _1
        let relPath2 = try vault.importFileData(samplePNGData, filename: "screenshot.png")
        #expect(relPath2 == "files/screenshot_1.png")

        let fullPath2 = (tempDir as NSString).appendingPathComponent("files/screenshot_1.png")
        #expect(FileManager.default.fileExists(atPath: fullPath2))
    }

    @Test("PataEmbeddedImageProvider resolves local relative, files/, absolute and percent-encoded paths")
    func imageProviderLocalResolution() throws {
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_provider_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }

        let filesDir = (tempDir as NSString).appendingPathComponent("files")
        let notesDir = (tempDir as NSString).appendingPathComponent("notes")
        try FileManager.default.createDirectory(atPath: filesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: notesDir, withIntermediateDirectories: true)

        let samplePNGData = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

        // Create standard image: files/flow.png
        let flowPath = (filesDir as NSString).appendingPathComponent("flow.png")
        try samplePNGData.write(to: URL(fileURLWithPath: flowPath))

        // Create image with unicode and spaces: files/架构 设计.png
        let unicodePath = (filesDir as NSString).appendingPathComponent("架构 设计.png")
        try samplePNGData.write(to: URL(fileURLWithPath: unicodePath))

        let noteFile = (notesDir as NSString).appendingPathComponent("architecture_n-1.md")
        let provider = PataEmbeddedImageProvider(vaultPath: tempDir, noteFilePath: noteFile)

        // 1. Standard relative path from Note: ../files/flow.png
        let req1 = EmbeddedImageRequest(name: "../files/flow.png")
        let img1 = provider.image(for: req1)
        #expect(img1 != nil)
        #expect(img1?.size.width ?? 0 > 0)

        // 2. Vault relative path: files/flow.png
        let req2 = EmbeddedImageRequest(name: "files/flow.png")
        let img2 = provider.image(for: req2)
        #expect(img2 != nil)

        // 3. Plain filename lookup: flow.png (like in ![[flow.png]])
        let req3 = EmbeddedImageRequest(name: "flow.png")
        let img3 = provider.image(for: req3)
        #expect(img3 != nil)

        // 4. Absolute path
        let req4 = EmbeddedImageRequest(name: flowPath)
        let img4 = provider.image(for: req4)
        #expect(img4 != nil)

        // 5. file:// URL
        let req5 = EmbeddedImageRequest(name: "file://\(flowPath)")
        let img5 = provider.image(for: req5)
        #expect(img5 != nil)

        // 6. Percent encoded unicode with spaces: ../files/%E6%9E%B6%E6%9E%84%20%E8%AE%BE%E8%AE%A1.png
        let encodedName = "../files/%E6%9E%B6%E6%9E%84%20%E8%AE%BE%E8%AE%A1.png"
        let req6 = EmbeddedImageRequest(name: encodedName)
        let img6 = provider.image(for: req6)
        #expect(img6 != nil)

        // 7. Markdown link with optional title: `../files/flow.png "Diagram Title"`
        let req7 = EmbeddedImageRequest(name: "../files/flow.png \"Diagram Title\"")
        let img7 = provider.image(for: req7)
        #expect(img7 != nil)

        // 8. Markdown link with query/fragment: `../files/flow.png#t=1`
        let req8 = EmbeddedImageRequest(name: "../files/flow.png#t=1")
        let img8 = provider.image(for: req8)
        #expect(img8 != nil)

        // 9. Non-existent file should safely return nil
        let req9 = EmbeddedImageRequest(name: "../files/non_existent.png")
        let img9 = provider.image(for: req9)
        #expect(img9 == nil)
    }

    @Test("PataEmbeddedImageProvider parses Base64 Data URIs")
    func imageProviderBase64DataURI() {
        let provider = PataEmbeddedImageProvider()

        let base64URI = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let req = EmbeddedImageRequest(name: base64URI)
        let img = provider.image(for: req)

        #expect(img != nil)
        #expect(img?.size.width == 1)
        #expect(img?.size.height == 1)
    }

    @Test("PataEmbeddedImageProvider fingerprint remains stable on size changes to prevent TextKit layout thrashing")
    func imageProviderFingerprintStableAcrossResize() {
        let p1 = PataEmbeddedImageProvider(vaultPath: "/v", noteFilePath: "/v/n.md", noteWidth: 600)
        let p2 = PataEmbeddedImageProvider(vaultPath: "/v", noteFilePath: "/v/n.md", noteWidth: 800)
        let pDiff = PataEmbeddedImageProvider(vaultPath: "/v", noteFilePath: "/v/other.md", noteWidth: 800)

        #expect(p1.fingerprint() == p2.fingerprint())
        #expect(p1.fingerprint() != pDiff.fingerprint())
    }

    @Test("Local image cache keys include the owning note directory")
    func imageCacheDoesNotCrossNoteDirectories() throws {
        let fixture = try AuditVaultFixture()
        let root = URL(fileURLWithPath: fixture.vault.rootPath)
        let firstDirectory = root.appendingPathComponent("notes/one")
        let secondDirectory = root.appendingPathComponent("notes/two")
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let name = "\(UUID().uuidString).png"
        let data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!
        try data.write(to: firstDirectory.appendingPathComponent(name))
        let first = PataEmbeddedImageProvider(vaultPath: root.path, noteFilePath: firstDirectory.appendingPathComponent("a.md").path)
        let second = PataEmbeddedImageProvider(vaultPath: root.path, noteFilePath: secondDirectory.appendingPathComponent("b.md").path)
        let request = EmbeddedImageRequest(name: name)
        let firstImage = try #require(first.image(for: request))
        #expect(second.image(for: request) == nil)
        try data.write(to: secondDirectory.appendingPathComponent(name))
        let secondImage = try #require(second.image(for: request))
        #expect(firstImage !== secondImage)
    }

    @Test("PataImageCache stores and invalidates correctly")
    func imageCacheLifecycle() {
        let key = "test_key_\(UUID().uuidString)"
        #expect(PataImageCache.shared.image(forKey: key) == nil)

        let image = NSImage(size: NSSize(width: 10, height: 10))
        PataImageCache.shared.setImage(image, forKey: key)
        #expect(PataImageCache.shared.image(forKey: key) != nil)

        PataImageCache.shared.remove(forKey: key)
        #expect(PataImageCache.shared.image(forKey: key) == nil)
    }
}
