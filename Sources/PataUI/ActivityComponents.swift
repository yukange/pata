import SwiftUI
import AppKit
import PataCore

public struct ActivityTextView: View {
    public let text: String
    @ObservedObject public var state: AppState

    public let noteRefs: [String: String]

    public init(text: String, state: AppState, noteRefs: [String: String] = [:]) {
        self.text = text
        self.state = state
        self.noteRefs = noteRefs
    }

    public var body: some View {
        Text(attributedText)
            .font(.system(size: 14))
            .foregroundColor(.primary)
            .lineSpacing(3)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "pata", url.host == "note" {
                    let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let decoded = path.removingPercentEncoding ?? path
                    if let targetId = noteDestination(named: decoded) {
                        state.navigateToNote(noteId: targetId)
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    func noteDestination(named name: String) -> String? {
        guard let vault = state.vault else { return nil }
        let notes = vault.index.listNotes().reduce(into: [String: Note]()) { $0[$1.id] = $1 }
        return Links.resolveTextRef(name: name, noteRefs: noteRefs, notes: notes)
    }

    private var attributedText: AttributedString {
        let converted = convertWikilinksToMarkdown(text: text)
        if let attr = try? AttributedString(markdown: converted, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return attr
        }
        return AttributedString(text)
    }

    private func convertWikilinksToMarkdown(text: String) -> String {
        let pattern = #"\\?\[\[([^\[\]\n]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        var result = ""
        var lastIndex = 0

        for match in matches {
            let fullRange = match.range(at: 0)
            let titleRange = match.range(at: 1)
            let fullStr = nsText.substring(with: fullRange)

            if fullStr.hasPrefix("\\") {
                continue
            }

            if fullRange.location > lastIndex {
                result += nsText.substring(with: NSRange(location: lastIndex, length: fullRange.location - lastIndex))
            }

            let title = nsText.substring(with: titleRange)
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            result += "[\\[[\(title)]\\]](pata://note/\(encoded))"
            lastIndex = fullRange.location + fullRange.length
        }

        if lastIndex < nsText.length {
            result += nsText.substring(with: NSRange(location: lastIndex, length: nsText.length - lastIndex))
        }

        return result
    }
}

extension Color {
    public static var emeraldColor: Color {
        Color(red: 4/255, green: 120/255, blue: 87/255)
    }
    public static var stoneBadgeBg: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }
    public static var stoneSelectedBg: Color {
        Color(nsColor: .selectedContentBackgroundColor).opacity(0.2)
    }
    public static var stoneTagBg: Color {
        Color(red: 4/255, green: 120/255, blue: 87/255).opacity(0.1)
    }
    public static var roseBadgeText: Color {
        Color(red: 225/255, green: 29/255, blue: 72/255)
    }
    public static var roseBadgeBg: Color {
        Color(red: 225/255, green: 29/255, blue: 72/255).opacity(0.12)
    }
    public static var amberBadgeText: Color {
        Color(red: 217/255, green: 119/255, blue: 6/255)
    }
    public static var amberBadgeBg: Color {
        Color(red: 217/255, green: 119/255, blue: 6/255).opacity(0.12)
    }
}
