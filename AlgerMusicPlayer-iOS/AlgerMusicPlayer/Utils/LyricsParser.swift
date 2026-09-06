import Foundation

struct LyricLine: Identifiable, Hashable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

enum LyricsParser {
    /// Parse LRC text into ordered lyric lines. Handles multiple timestamps
    /// on a single line and `[mm:ss.xx]` / `[mm:ss.xxx]` formats.
    static func parse(_ raw: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#) else {
            return lines
        }
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let ns = trimmed as NSString
            let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
            guard let first = matches.first else { continue }

            let minute = Int(ns.substring(with: first.range(at: 1))) ?? 0
            let second = Int(ns.substring(with: first.range(at: 2))) ?? 0
            let fracRaw = first.range(at: 3).location != NSNotFound
                ? ns.substring(with: first.range(at: 3)) : "0"
            let frac = Double("0.\(fracRaw)") ?? 0
            let time = TimeInterval(minute * 60 + second) + frac

            var text = trimmed
            for m in matches {
                text = (text as NSString).replacingCharacters(in: m.range, with: "")
            }
            text = text.trimmingCharacters(in: .whitespaces)
            if text.isEmpty { text = "♪" }
            lines.append(LyricLine(time: time, text: text))
        }
        return lines.sorted { $0.time < $1.time }
    }
}
