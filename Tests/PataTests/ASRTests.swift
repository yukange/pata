import Testing
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
}
