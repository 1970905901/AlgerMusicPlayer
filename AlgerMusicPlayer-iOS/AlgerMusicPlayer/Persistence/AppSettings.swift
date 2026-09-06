import Foundation
import Combine

enum AudioQuality: String, CaseIterable, Identifiable {
    case standard = "standard"
    case higher = "higher"
    case exhigh = "exhigh"
    case lossless = "lossless"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "标准"
        case .higher: return "较高"
        case .exhigh: return "极高"
        case .lossless: return "无损"
        }
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

/// App-wide, persisted settings. Lives as a singleton injected as an
/// EnvironmentObject. Persists to UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var apiBaseURL: String {
        didSet { persist() }
    }
    @Published var audioQuality: AudioQuality {
        didSet { persist() }
    }
    @Published var themeMode: ThemeMode {
        didSet { persist() }
    }
    @Published var playbackRate: Double {
        didSet { persist() }
    }
    /// NetEase `MUSIC_U` cookie for account features (cloud playlists).
    @Published var musicUCookie: String {
        didSet { persist() }
    }
    @Published var userId: Int {
        didSet { persist() }
    }

    private init() {
        let d = UserDefaults.standard
        self.apiBaseURL = d.string(forKey: "apiBaseURL") ?? "https://music.alger.fun"
        self.audioQuality = AudioQuality(rawValue: d.string(forKey: "audioQuality") ?? "") ?? .standard
        self.themeMode = ThemeMode(rawValue: d.string(forKey: "themeMode") ?? "") ?? .system
        self.playbackRate = d.object(forKey: "playbackRate") as? Double ?? 1.0
        self.musicUCookie = d.string(forKey: "musicUCookie") ?? ""
        self.userId = d.integer(forKey: "userId")
    }

    func persist() {
        let d = UserDefaults.standard
        d.set(apiBaseURL, forKey: "apiBaseURL")
        d.set(audioQuality.rawValue, forKey: "audioQuality")
        d.set(themeMode.rawValue, forKey: "themeMode")
        d.set(playbackRate, forKey: "playbackRate")
        d.set(musicUCookie, forKey: "musicUCookie")
        d.set(userId, forKey: "userId")
    }
}
