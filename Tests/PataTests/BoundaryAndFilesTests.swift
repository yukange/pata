import Testing
import Foundation
@testable import PataCore

@Suite("BDD Feature: Vault Boundaries, File Indexing & Security")
struct BoundaryAndFilesTests {

    @Test("Given files placed outside business directories (e.g. root README.md, docs/), when scanning vault, then they are not indexed as notes")
    func nonBusinessFilesNotIndexedAsNotesScenario() throws {
        // Given: A vault containing non-business files in root and docs/
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_boundary_\(UUID().uuidString)")
        let docsDir = tmpDir.appendingPathComponent("docs")
        let notesDir = tmpDir.appendingPathComponent("notes")
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Root readme
        try "# Root Readme\n不应被作为笔记".write(
            to: tmpDir.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        // Docs guide
        try "# Developer Guide\n项目文档".write(
            to: docsDir.appendingPathComponent("guide.md"),
            atomically: true,
            encoding: .utf8
        )
        // Actual note in notes/
        try "---\ntype: note\nid: n-real-01\ntitle: 真实笔记\ncreated_at: 2026-10-16T10:00:00+08:00\nupdated_at: 2026-10-16T10:00:00+08:00\n---\n正文".write(
            to: notesDir.appendingPathComponent("real.md"),
            atomically: true,
            encoding: .utf8
        )

        // When: The vault is scanned
        let vault = try Vault(rootPath: tmpDir.path)

        // Then: Only the note in notes/ is indexed
        let notes = vault.index.listNotes()
        #expect(notes.count == 1)
        #expect(notes.first?.id == "n-real-01")
        #expect(notes.contains { $0.title == "Root Readme" } == false)
        #expect(notes.contains { $0.title == "Developer Guide" } == false)
    }

    @Test("Given files in files/ directory and subdirectories, when scanning vault, then they are indexed as file resources and searchable by name and subpath")
    func filesDirectoryIndexedAndSearchableScenario() throws {
        // Given: A vault containing media and documents in files/ and files/sub/
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_files_res_\(UUID().uuidString)")
        let filesDir = tmpDir.appendingPathComponent("files")
        let subFilesDir = filesDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subFilesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let docPDF = filesDir.appendingPathComponent("document.pdf")
        let dummyPDF = Data("%PDF-1.4 dummy pdf data".utf8)
        try dummyPDF.write(to: docPDF)

        let subImage = subFilesDir.appendingPathComponent("architecture.png")
        let dummyPNG = Data("fake png bytes".utf8)
        try dummyPNG.write(to: subImage)

        // When: The vault is scanned
        let vault = try Vault(rootPath: tmpDir.path)

        // Then: File resources are correctly indexed
        let fileList = vault.index.listFiles()
        #expect(fileList.count == 2)

        let pdfRes = vault.index.getFileResource(relativePath: "files/document.pdf")
        #expect(pdfRes != nil)
        #expect(pdfRes?.name == "document.pdf")
        #expect(pdfRes?.ext == ".pdf")
        #expect(pdfRes?.size == Int64(dummyPDF.count))

        let imgRes = vault.index.getFileResource(relativePath: "files/sub/architecture.png")
        #expect(imgRes != nil)
        #expect(imgRes?.name == "architecture.png")
        #expect(imgRes?.ext == ".png")

        // And: Search discovers the files by name and relative path
        let searchDoc = vault.index.searchAll("document")
        #expect(!searchDoc.isEmpty)
        #expect(searchDoc.first?.type == .file)
        #expect(searchDoc.first?.title == "document.pdf")

        let searchSub = vault.index.searchAll("sub/architecture")
        #expect(!searchSub.isEmpty)
        #expect(searchSub.first?.type == .file)
        #expect(searchSub.first?.title == "architecture.png")
    }

    @Test("Given a path attempting parent directory traversal (../), when resolving vault path, then traversal attempt is rejected")
    func pathTraversalAttemptRejectedScenario() throws {
        // Given: A vault root path
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_sec_traversal_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // When: Resolving paths containing parent traversal
        // Then: Throws PathSafetyError.pathEscapesVault
        #expect(throws: Safety.PathSafetyError.self) {
            try Safety.safeResolveVaultPath(vaultRoot: tmpDir.path, targetPath: "../outside.txt")
        }

        #expect(throws: Safety.PathSafetyError.self) {
            try Safety.safeResolveVaultPath(vaultRoot: tmpDir.path, targetPath: "files/../../outside.txt")
        }

        // And: Valid relative subpaths resolve properly
        let (abs, rel) = try Safety.safeResolveVaultPath(vaultRoot: tmpDir.path, targetPath: "tasks/../files/doc.pdf")
        #expect(rel == "files/doc.pdf")
        #expect(abs.hasSuffix("files/doc.pdf"))
    }

    @Test("Given a symlink pointing outside the vault, when resolving path, then symlink escape is strictly prevented")
    func symlinkEscapePreventedScenario() throws {
        // Given: A vault and a secret file in an outside directory
        let vaultDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_vault_symlink_\(UUID().uuidString)")
        let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_bdd_outside_\(UUID().uuidString)")
        let filesDir = vaultDir.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vaultDir)
            try? FileManager.default.removeItem(at: outsideDir)
        }

        let secretFile = outsideDir.appendingPathComponent("secret.txt")
        try "机密配置".write(to: secretFile, atomically: true, encoding: .utf8)

        // And: A symlink inside vault/files/ pointing to the secret file outside
        let linkPath = filesDir.appendingPathComponent("leak.txt").path
        try FileManager.default.createSymbolicLink(atPath: linkPath, withDestinationPath: secretFile.path)

        // When: Attempting to resolve the symlinked file
        // Then: Symlink escape is detected and rejected
        #expect(throws: Safety.PathSafetyError.self) {
            try Safety.safeResolveVaultPath(vaultRoot: vaultDir.path, targetPath: "files/leak.txt")
        }
    }
}
