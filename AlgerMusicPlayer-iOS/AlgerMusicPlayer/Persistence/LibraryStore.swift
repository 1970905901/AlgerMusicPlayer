import Foundation
import Combine

/// Local library (favorites + user playlists) persisted as JSON files in
/// the app's Application Support directory. No CoreData/SwiftData needed,
/// which keeps the project buildable on iOS 16.5.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var favorites: [StoredTrack] = []
    @Published private(set) var playlists: [LocalPlaylist] = []

    /// Track currently awaiting "add to playlist" selection (drives a sheet).
    @Published var pendingAddTrack: Track? = nil

    private let fm = FileManager.default

    private var directory: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("AlgerMusic", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var favoriteFile: URL { directory.appendingPathComponent("favorites.json") }
    private var playlistFile: URL { directory.appendingPathComponent("playlists.json") }

    private init() { load() }

    func load() {
        if let d = try? Data(contentsOf: favoriteFile),
           let arr = try? JSONDecoder().decode([StoredTrack].self, from: d) {
            favorites = arr
        }
        if let d = try? Data(contentsOf: playlistFile),
           let arr = try? JSONDecoder().decode([LocalPlaylist].self, from: d) {
            playlists = arr
        }
    }

    private func saveFavorites() {
        try? JSONEncoder().encode(favorites).write(to: favoriteFile)
    }
    private func savePlaylists() {
        try? JSONEncoder().encode(playlists).write(to: playlistFile)
    }

    // MARK: Favorites

    func isFavorite(_ id: Int) -> Bool { favorites.contains { $0.id == id } }

    func toggleFavorite(_ t: Track) {
        if isFavorite(t.id) {
            favorites.removeAll { $0.id == t.id }
        } else {
            favorites.insert(t.toStored(), at: 0)
        }
        saveFavorites()
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(name: String) -> LocalPlaylist {
        let pl = LocalPlaylist(id: UUID(), name: name, tracks: [], createdAt: Date())
        playlists.insert(pl, at: 0)
        savePlaylists()
        return pl
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
    }

    func add(_ track: Track, to id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        if !playlists[idx].tracks.contains(where: { $0.id == track.id }) {
            playlists[idx].tracks.append(track.toStored())
            savePlaylists()
        }
    }

    func remove(_ trackId: Int, from id: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].tracks.removeAll { $0.id == trackId }
        savePlaylists()
    }

    func requestAdd(_ track: Track) {
        pendingAddTrack = track
    }

    func resolveAddTo(_ id: UUID) {
        guard let t = pendingAddTrack else { return }
        add(t, to: id)
        pendingAddTrack = nil
    }

    func cancelAdd() { pendingAddTrack = nil }
}
