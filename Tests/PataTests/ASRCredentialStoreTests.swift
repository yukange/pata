import Foundation
import Testing
import PataAudio
@testable import PataUI

@Suite("ASR file credentials")
struct ASRCredentialStoreTests {
    @Test func savesPrivatelyAndSurvivesReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pata/asr.json")
        let store = ASRCredentialStore(fileURL: url)
        #expect(try store.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        try store.save("  test-only-key\n")
        #expect(try ASRCredentialStore(fileURL: url).load() == "test-only-key")
        let file = try FileManager.default.attributesOfItem(atPath: url.path)
        let directory = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((directory[.posixPermissions] as? NSNumber)?.intValue == 0o700)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        try store.save("replacement-test-key")
        #expect(try store.load() == "replacement-test-key")
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == ["asr.json"])
        #expect(throws: ASRCredentialStore.StoreError.self) { try store.save(" \n ") }
        #expect(try store.load() == "replacement-test-key")
    }

    @Test func malformedFileDoesNotExposeContentsOrGetOverwrittenByReading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("asr.json")
        let malformed = Data("{ invalid test-only-secret }".utf8)
        try malformed.write(to: url)
        do {
            _ = try ASRCredentialStore(fileURL: url).load()
            Issue.record("Malformed credentials must report an error")
        } catch {
            #expect(!error.localizedDescription.contains("test-only-secret"))
        }
        #expect(try Data(contentsOf: url) == malformed)
    }

    @Test @MainActor func appStateUsesFileAndReportsSaveAndReadFailures() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("pata/asr.json")
        let state = AppState(loadPreferences: false, watchDayRollover: false,
                             asrCredentials: ASRCredentialStore(fileURL: url))
        state.checkASRKey()
        #expect(!state.isASRConfigured)
        try state.setASRKey("test-only-key")
        #expect(state.isASRConfigured)
        #expect(state.readASRKey() == "test-only-key")
        #expect(throws: ASRCredentialStore.StoreError.self) { try state.setASRKey(" ") }
        #expect(state.isASRConfigured)
        #expect(state.asrKeyError != nil)
        #expect(state.readASRKey() == "test-only-key")
        #expect(state.asrKeyError == nil)

        try Data("not JSON".utf8).write(to: url)
        state.checkASRKey()
        #expect(!state.isASRConfigured)
        #expect(state.asrKeyError != nil)
        try state.setASRKey("recovered-test-key")
        #expect(state.isASRConfigured)
        #expect(state.asrKeyError == nil)

        let blocked = root.appendingPathComponent("blocked")
        try Data("existing file".utf8).write(to: blocked)
        let failed = AppState(loadPreferences: false, watchDayRollover: false,
                              asrCredentials: ASRCredentialStore(fileURL: blocked.appendingPathComponent("asr.json")))
        #expect(throws: (any Error).self) { try failed.setASRKey("test-only-key") }
        #expect(failed.asrKeyError != nil)
        #expect(!failed.isASRConfigured)
        #expect(try String(contentsOf: blocked, encoding: .utf8) == "existing file")
    }
}
