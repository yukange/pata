import Testing
@testable import PataCore
import Foundation

@Suite("Safety Tests")
struct SafetyTests {
    @Test("Atomic write, baseline check, and conflict detection")
    func atomicWriteAndBaselineCheck() throws {
        let tempDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("pata_safety_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(atPath: tempDir)
        }

        let filePath = (tempDir as NSString).appendingPathComponent("doc.md")
        let tracker = WriteTracker()

        // 1. Initial write
        let content1 = "Initial Content"
        let base1 = try Safety.safeWrite(targetPath: filePath, data: Data(content1.utf8), baseline: nil, tracker: tracker)
        #expect(base1.path == URL(fileURLWithPath: filePath).standardized.path)

        // Verify written content
        let readData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        #expect(String(data: readData, encoding: .utf8) == content1)

        // 2. Safe update with valid baseline
        let content2 = "Updated Content"
        let base2 = try Safety.safeWrite(targetPath: filePath, data: Data(content2.utf8), baseline: base1, tracker: tracker)
        #expect(base1.hash != base2.hash)

        // 3. Stale baseline conflict rejection
        let content3 = "Stale update"
        #expect(throws: ConflictError.self) {
            try Safety.safeWrite(targetPath: filePath, data: Data(content3.utf8), baseline: base1, tracker: tracker)
        }
    }
}
