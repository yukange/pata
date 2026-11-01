import Foundation

public struct AudioInspectionResult: Sendable {
    public let channels: Int
    public let durationSec: Double

    public init(channels: Int, durationSec: Double) {
        self.channels = channels
        self.durationSec = durationSec
    }
}

public enum AudioPreprocessor {
    /// Inspects audio channels and duration using macOS afinfo.
    public static func inspectAudio(url: URL) -> AudioInspectionResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afinfo")
        proc.arguments = [url.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                var channels = 2
                var duration = 0.0

                // Parse channels: e.g. "Data format: 1 ch" or "2 channels"
                if let match = output.range(of: #"(\d+)\s+ch(?:annel)?"#, options: .regularExpression) {
                    let sub = output[match]
                    let digits = sub.filter { $0.isNumber }
                    if let c = Int(digits), c > 0 {
                        channels = c
                    }
                }

                // Parse duration: e.g. "estimated duration: 123.456 sec"
                if let match = output.range(of: #"estimated duration:\s*([0-9.]+)\s*sec"#, options: .regularExpression) {
                    let sub = output[match]
                    let numStr = sub.replacingOccurrences(of: "estimated duration:", with: "")
                        .replacingOccurrences(of: "sec", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let d = Double(numStr) {
                        duration = d
                    }
                }

                return AudioInspectionResult(channels: channels, durationSec: duration)
            }
        } catch {
            // afinfo fallback
        }

        return AudioInspectionResult(channels: 2, durationSec: 0)
    }

    /// Prepares audio for DashScope speaker diarization (ensuring mono audio).
    /// If multi-channel, uses afconvert to generate a temporary mono copy.
    public static func prepareAudioForTranscription(url: URL) async -> (targetURL: URL, warning: String?, cleanup: @Sendable () -> Void) {
        await _Concurrency.Task.detached(priority: .userInitiated) {
            prepareAudioSynchronously(url: url)
        }.value
    }

    private static func prepareAudioSynchronously(url: URL) -> (targetURL: URL, warning: String?, cleanup: @Sendable () -> Void) {
        assert(!Thread.isMainThread)
        let info = inspectAudio(url: url)
        var warning: String? = nil
        if info.durationSec > 7200 {
            warning = "音频时长超过 2 小时建议上限，说话人分离可能耗时较长或处理受限"
        }

        if info.channels <= 1 {
            return (url, warning, {})
        }

        // Stereo or multi-channel: convert to mono using macOS afconvert
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pata_mono_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let monoURL = tempDir.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).m4a")

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            proc.arguments = ["-f", "m4af", "-d", "aac", "-c", "1", url.path, monoURL.path]
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: monoURL.path) {
                let cleanup: @Sendable () -> Void = {
                    _ = try? FileManager.default.removeItem(at: tempDir)
                }
                return (monoURL, warning, cleanup)
            }
        } catch {
            // If conversion fails, fallback to original
        }

        try? FileManager.default.removeItem(at: tempDir)
        return (url, warning, {})
    }
}
