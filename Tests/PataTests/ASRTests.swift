import Testing
import Foundation
import AVFoundation
@testable import PataAudio

@Suite("ASR Tests")
struct ASRTests {
    @Test("Format milliseconds to HH:mm:ss.SSS")
    func millisecondFormatting() {
        #expect(ASRFormatter.formatMilliseconds(0) == "00:00:00.000")
        #expect(ASRFormatter.formatMilliseconds(65230) == "00:01:05.230")
        #expect(ASRFormatter.formatMilliseconds(3661005) == "01:01:01.005")
    }

    @Test("Parse timestamp string to milliseconds")
    func millisecondParsing() {
        #expect(ASRFormatter.parseMilliseconds("00:00:00.000") == 0)
        #expect(ASRFormatter.parseMilliseconds("00:01:05.230") == 65230)
        #expect(ASRFormatter.parseMilliseconds("01:01:01.005") == 3661005)
        #expect(ASRFormatter.parseMilliseconds("#t=00:01:05.230") == 65230)
    }

    @Test("Generate transcript markdown with timestamps")
    func transcriptGeneration() {
        let sentences = [
            ASRSentence(beginTime: 1000, endTime: 3000, text: "Hello world.", speakerId: 0),
            ASRSentence(beginTime: 3500, endTime: 5000, text: "Second sentence.", speakerId: 1)
        ]
        let md = ASRFormatter.formatTranscript(sentences: sentences)
        #expect(md.contains("[00:00:01.000](#t=00:00:01.000)"))
        #expect(md.contains("说话人"))
        #expect(md.contains("Hello world."))
        #expect(md.contains("[00:00:03.500](#t=00:00:03.500)"))
        #expect(md.contains("说话人 1"))
        #expect(md.contains("Second sentence."))
    }

    @Test("UploadPolicy JSON parsing with optional ACL fields")
    func uploadPolicyParsing() throws {
        let json = """
        {
            "policy": "eyJleHBpcmF0aW9uIjoiMjAyNi0xMC0zMVQxMTo...",
            "signature": "abcdef123456",
            "upload_dir": "dashscope-audio/uploads",
            "upload_host": "https://dashscope-result-sh.oss-cn-shanghai.aliyuncs.com",
            "oss_access_key_id": "LTAI5t...",
            "x_oss_object_acl": "private",
            "x_oss_forbid_overwrite": "true"
        }
        """
        let data = Data(json.utf8)
        let policy = try JSONDecoder().decode(UploadPolicy.self, from: data)
        #expect(policy.policy.starts(with: "eyJleHBpcmF0aW9u"))
        #expect(policy.signature == "abcdef123456")
        #expect(policy.uploadDir == "dashscope-audio/uploads")
        #expect(policy.ossAccessKeyId == "LTAI5t...")
        #expect(policy.xOssObjectAcl == "private")
        #expect(policy.xOssForbidOverwrite == "true")
    }

    @Test("Audio preparation can be awaited from MainActor and produces a mono copy")
    @MainActor
    func preparesStereoAudioOffMainThread() async throws {
        let fixture = try AuditVaultFixture()
        let url = fixture.directory.appendingPathComponent("stereo.wav")
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
        buffer.frameLength = 44100
        let channels = try #require(buffer.floatChannelData)
        for channel in 0..<2 { channels[channel].initialize(repeating: 0, count: 44100) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
        }
        let prepared = await AudioPreprocessor.prepareAudioForTranscription(url: url)
        defer { prepared.cleanup() }
        #expect(prepared.targetURL != url)
        let mono = try AVAudioFile(forReading: prepared.targetURL)
        #expect(mono.processingFormat.channelCount == 1)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("ASRManager state machine, discard and confirm replace flow")
    @MainActor
    func asrManagerFlow() throws {
        let mgr = ASRManager()
        let noteId = "note-test-asr-123"

        // Initial state is idle
        let initStatus = mgr.getStatus(for: noteId)
        #expect(initStatus.state == .idle)

        // Cancel task on empty is safe
        mgr.cancelTask(noteId: noteId)
        #expect(mgr.getStatus(for: noteId).state == .idle)
    }
}
