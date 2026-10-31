import Testing
import Foundation
@testable import PataCore
@testable import PataAudio
@testable import PataEditor

@Suite("BDD Feature: Audio Transcript Voice Note Lifecycle")
struct AudioNoteScenarioTests {

    @Test("Timestamp parser correctly parses multiple variations of #t= timestamps")
    func testTimestampParser() {
        #expect(PataTimestampParser.parseMilliseconds("00:01:05.230") == 65230)
        #expect(PataTimestampParser.parseMilliseconds("#t=00:00:01.200") == 1200)
        #expect(PataTimestampParser.parseMilliseconds("https://#t=00:02:10.500") == 130500)
        #expect(PataTimestampParser.parseMilliseconds("files/meeting.mp3#t=00:00:03.600") == 3600)
        #expect(PataTimestampParser.parseMilliseconds("invalid") == nil)
    }

    @Test("Transcript locator correctly locates sentence ranges by target timestamp")
    func testTranscriptLocator() {
        let transcript = """
        [00:00:01.200](#t=00:00:01.200) 说话人 1

        大家好，今天开始周会。

        [00:00:03.600](#t=00:00:03.600) 说话人 2

        各项进展顺利。
        """

        // Target before first sentence -> returns first sentence
        let rangeBefore = PataTranscriptLocator.findSentenceRange(in: transcript, targetMs: 500)
        #expect(rangeBefore != nil)
        let matchedLineBefore = (transcript as NSString).substring(with: rangeBefore!)
        #expect(matchedLineBefore.contains("00:00:01.200"))

        // Target right on second sentence -> returns second sentence
        let rangeExact = PataTranscriptLocator.findSentenceRange(in: transcript, targetMs: 3600)
        #expect(rangeExact != nil)
        let matchedLineExact = (transcript as NSString).substring(with: rangeExact!)
        #expect(matchedLineExact.contains("00:00:03.600"))

        // Target between first and second sentence (e.g. 2500ms) -> returns nearest earlier sentence (first)
        let rangeBetween = PataTranscriptLocator.findSentenceRange(in: transcript, targetMs: 2500)
        #expect(rangeBetween != nil)
        let matchedLineBetween = (transcript as NSString).substring(with: rangeBetween!)
        #expect(matchedLineBetween.contains("00:00:01.200"))
    }

    @Test("Given an audio file, when imported and note created, then audio_transcript and audio_file are persisted correctly")
    func audioNoteCreationAndPersistenceScenario() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("pata_audio_note_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Create a dummy audio file
        let dummyAudioURL = tmpDir.appendingPathComponent("sample_meeting.mp3")
        try Data("ID3dummy_audio_bytes".utf8).write(to: dummyAudioURL)

        let vault = try Vault(rootPath: tmpDir.path)

        // 1. Import file to files/
        let relPath = try vault.importFile(sourceURL: dummyAudioURL)
        #expect(relPath.hasPrefix("files/"))
        #expect(relPath.hasSuffix(".mp3"))

        // 2. Create audio transcript note
        let note = try vault.createNote(
            title: "sample_meeting",
            body: "",
            tags: ["会议"],
            draft: false,
            audioFile: relPath,
            audioTranscript: true
        )

        #expect(note.audioTranscript == true)
        #expect(note.audioFile == relPath)
        #expect(note.title == "sample_meeting")

        // 3. Verify disk file and frontmatter
        let notePath = vault.resolveEntityPath(note)
        #expect(FileManager.default.fileExists(atPath: notePath))

        let content = try String(contentsOfFile: notePath, encoding: .utf8)
        #expect(content.contains("audio_transcript: true"))
        #expect(content.contains("audio_file: \(relPath)"))

        // 4. Update note with transcript
        let sentences = [
            ASRSentence(beginTime: 1200, endTime: 3400, text: "大家好，今天开始周会。", speakerId: 1),
            ASRSentence(beginTime: 3600, endTime: 5800, text: "各项进展顺利。", speakerId: 2)
        ]
        let formattedTranscript = ASRFormatter.formatTranscript(sentences: sentences)

        var updated = note
        updated.body = formattedTranscript
        _ = try vault.updateNote(updated)

        // 5. Read back from disk and check parsed Note
        let updatedContent = try String(contentsOfFile: notePath, encoding: .utf8)
        let parsed = try Frontmatter.parseMarkdown(filePath: notePath, content: updatedContent) as? Note
        #expect(parsed != nil)
        #expect(parsed?.audioTranscript == true)
        #expect(parsed?.audioFile == relPath)
        #expect(parsed?.body.contains("[00:00:01.200](#t=00:00:01.200) 说话人 1") == true)
        #expect(parsed?.body.contains("大家好，今天开始周会。") == true)
    }
}
