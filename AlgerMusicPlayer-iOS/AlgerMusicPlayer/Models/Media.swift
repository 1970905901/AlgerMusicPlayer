import Foundation

/// Brief playlist card (from /top/playlist, /search, /user/playlist, etc.)
struct PlaylistBrief: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let trackCount: Int
    let creatorName: String?
    let playCount: Int?
}

struct Playlist: Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let creatorName: String?
    let tracks: [Track]
}

struct Album: Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let artistName: String?
    let tracks: [Track]
}

struct AlbumBrief: Identifiable, Hashable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let artistName: String?
}

struct ArtistBrief: Identifiable, Hashable {
    let id: Int
    let name: String
    let coverURL: String?
}

struct Artist: Identifiable {
    let id: Int
    let name: String
    let coverURL: String?
}

/// Navigation routes used by NavigationStack stacks.
enum Route: Hashable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
}
