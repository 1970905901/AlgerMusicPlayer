import Foundation
import SwiftUI

extension TimeInterval {
    var mmss: String {
        guard self.isFinite, self >= 0 else { return "00:00" }
        let total = Int(self)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

func formatCount(_ n: Int?) -> String {
    guard let n = n else { return "" }
    if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 1e8) }
    if n >= 10_000 { return String(format: "%.1f万", Double(n) / 1e4) }
    return "\(n)"
}

extension URL {
    /// Append query items, percent-encoding values automatically.
    func withQueries(_ items: [URLQueryItem]) -> URL? {
        guard var comp = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        comp.queryItems = items
        return comp.url
    }
}
