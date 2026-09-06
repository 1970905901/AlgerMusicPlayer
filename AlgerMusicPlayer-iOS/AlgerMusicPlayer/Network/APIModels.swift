import Foundation

// MARK: - Raw response models (match netease-cloud-music-api JSON shapes)

struct RawArtist: Codable {
    let id: Int?
    let name: String
    let picUrl: String?
    let img1v1Url: String?
}

struct RawAlbum: Codable {
    let id: Int?
    let name: String?
    let picUrl: String?
}

/// Songs arrive with two different key conventions depending on the endpoint
/// (search uses `artists`/`album`/`duration`, detail uses `ar`/`al`/`dt`).
struct RawSong: Codable {
    let id: Int
    let name: String
    let artists: [RawArtist]?
    let ar: [RawArtist]?
    let album: RawAlbum?
    let al: RawAlbum?
    let duration: Int?
    let dt: Int?
    let fee: Int?
}

struct SearchResponse: Codable {
    struct Result: Codable {
        let songCount: Int?
        let songs: [RawSong]?
        let albums: [RawSearchAlbum]?
        let artists: [RawSearchArtist]?
        let playlists: [RawSearchPlaylist]?
    }
    let result: Result?
    let code: Int?
}

struct RawSearchAlbum: Codable {
    let id: Int
    let name: String
    let artist: RawArtist?
    let picUrl: String?
}

struct RawSearchArtist: Codable {
    let id: Int
    let name: String
    let picUrl: String?
    let img1v1Url: String?
    let albumSize: Int?
}

struct RawSearchPlaylist: Codable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let description: String?
    let trackCount: Int?
    let playCount: Int?
    let creator: RawCreator?
}

struct RawCreator: Codable {
    let userId: Int?
    let nickname: String?
}

struct SongURLResponse: Codable {
    struct Datum: Codable {
        let id: Int
        let url: String?
        let level: String?
        let md5: String?
        let time: Int?
        let type: String?
    }
    let data: [Datum]?
    let code: Int?
}

struct LyricResponse: Codable {
    struct Lrc: Codable {
        let version: Int?
        let lyric: String?
    }
    let lrc: Lrc?
    let tlyric: Lrc?
    let code: Int?
}

struct PlaylistDetailResponse: Codable {
    struct Playlist: Codable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let description: String?
        let trackCount: Int?
        let creator: RawCreator?
        let tracks: [RawSong]?
    }
    let playlist: Playlist?
    let code: Int?
}

struct AlbumResponse: Codable {
    struct Album: Codable {
        let id: Int
        let name: String
        let picUrl: String?
        let artist: RawArtist?
    }
    let album: Album?
    let songs: [RawSong]?
    let code: Int?
}

struct ArtistTopResponse: Codable {
    let artist: RawArtist?
    let songs: [RawSong]?
    let code: Int?
}

struct TopPlaylistResponse: Codable {
    struct Item: Codable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let description: String?
        let trackCount: Int?
        let playCount: Int?
        let creator: RawCreator?
    }
    let playlists: [Item]?
    let total: Int?
    let code: Int?
}

struct UserPlaylistResponse: Codable {
    struct Item: Codable {
        let id: Int
        let name: String
        let coverImgUrl: String?
        let description: String?
        let trackCount: Int?
        let creator: RawCreator?
    }
    let playlist: [Item]?
    let code: Int?
}
