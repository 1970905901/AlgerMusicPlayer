import Foundation

/// Unified track model used across the whole app (renderer-agnostic).
struct Track: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let artistNames: String
    let albumName: String
    let coverURL: String?
    let duration: Double // seconds
    var url: String?

    var displayArtist: String { artistNames.isEmpty ? "未知歌手" : artistNames }
    var displayAlbum: String { albumName.isEmpty ? "未知专辑" : albumName }

    func toStored() -> StoredTrack {
        StoredTrack(id: id, name: name, artistNames: artistNames,
                    albumName: albumName, coverURL: coverURL, duration: duration)
    }
}

/// A serializable snapshot of a track for local persistence.
struct StoredTrack: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let artistNames: String
    let albumName: String
    let coverURL: String?
    let duration: Double

    var track: Track {
        Track(id: id, name: name, artistNames: artistNames,
              albumName: albumName, coverURL: coverURL, duration: duration, url: nil)
    }
}

/// A local (on-device) playlist.
struct LocalPlaylist: Codable, Identifiable {
    let id: UUID
    var name: String
    var tracks: [StoredTrack]
    let createdAt: Date
}
