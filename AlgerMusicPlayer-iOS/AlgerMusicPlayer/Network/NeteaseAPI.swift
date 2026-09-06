import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case empty
    case encoding
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回无效"
        case .empty: return "未找到内容"
        case .encoding: return "请求编码失败"
        }
    }
}

/// Thin async client over a `netease-cloud-music-api-alger` (or compatible)
/// server. All NetEase request signing happens server-side, so we only send
/// plain HTTP requests.
struct NeteaseAPI {
    static let shared = NeteaseAPI()
    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 16_5 like Mac OS X)"]
        cfg.timeoutIntervalForRequest = 25
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: cfg)
    }

    private var baseURL: String {
        let raw = AppSettings.shared.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = raw.isEmpty ? "https://music.alger.fun" : raw
        return trimmed.last == "/" ? String(trimmed.dropLast()) : trimmed
    }

    private var cookieHeader: String? {
        let c = AppSettings.shared.musicUCookie
        return c.isEmpty ? nil : "MUSIC_U=\(c)"
    }

    private func request(_ path: String,
                         query: [URLQueryItem] = [],
                         method: String = "GET",
                         form: [String: String]? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseURL + path)?.withQueries(query) else {
            throw APIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let c = cookieHeader { req.setValue(c, forHTTPHeaderField: "Cookie") }
        if let form = form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = form.map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
                .data(using: .utf8)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 { throw APIError.invalidResponse }
        return (data, http)
    }

    // MARK: Mapping

    private func map(_ s: RawSong) -> Track {
        let arts = s.artists ?? s.ar ?? []
        let artistNames = arts.map { $0.name }.joined(separator: " / ")
        let alb = s.album ?? s.al
        let cover = alb?.picUrl
        let dur = Double(s.duration ?? s.dt ?? 0) / 1000.0
        return Track(id: s.id, name: s.name, artistNames: artistNames,
                     albumName: alb?.name ?? "", coverURL: cover, duration: dur, url: nil)
    }

    // MARK: Endpoints

    func searchSongs(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [Track] {
        let (data, _) = try await request("/search", query: [
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.songs ?? []).map { map($0) }
    }

    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [AlbumBrief] {
        let (data, _) = try await request("/search", query: [
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "type", value: "10"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.albums ?? []).map {
            AlbumBrief(id: $0.id, name: $0.name, coverImgUrl: $0.picUrl, artistName: $0.artist?.name)
        }
    }

    func searchPlaylists(keyword: String, limit: Int = 30) async throws -> [PlaylistBrief] {
        let (data, _) = try await request("/search", query: [
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "type", value: "1000"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func searchArtists(keyword: String, limit: Int = 30) async throws -> [ArtistBrief] {
        let (data, _) = try await request("/search", query: [
            URLQueryItem(name: "keywords", value: keyword),
            URLQueryItem(name: "type", value: "100"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.artists ?? []).map {
            ArtistBrief(id: $0.id, name: $0.name, coverURL: $0.picUrl ?? $0.img1v1Url)
        }
    }

    func songURL(id: Int, level: String = "standard") async throws -> String? {
        let (data, _) = try await request("/song/url/v1", query: [
            URLQueryItem(name: "id", value: String(id)),
            URLQueryItem(name: "level", value: level),
        ])
        let dec = try JSONDecoder().decode(SongURLResponse.self, from: data)
        return dec.data?.first?.url
    }

    /// Download the raw audio data for a track (used for offline playback).
    func download(id: Int) async throws -> Data {
        guard let urlStr = try await songURL(id: id, level: AppSettings.shared.audioQuality.rawValue),
              let u = URL(string: urlStr) else { throw APIError.empty }
        let (data, _) = try await session.data(from: u)
        return data
    }

    func lyric(id: Int) async throws -> (String, String) {
        let (data, _) = try await request("/lyric", query: [URLQueryItem(name: "id", value: String(id))])
        let dec = try JSONDecoder().decode(LyricResponse.self, from: data)
        return (dec.lrc?.lyric ?? "", dec.tlyric?.lyric ?? "")
    }

    func playlistDetail(id: Int) async throws -> Playlist {
        let (data, _) = try await request("/playlist/detail", query: [URLQueryItem(name: "id", value: String(id))])
        let dec = try JSONDecoder().decode(PlaylistDetailResponse.self, from: data)
        guard let p = dec.playlist else { throw APIError.empty }
        let tracks = (p.tracks ?? []).map { map($0) }
        return Playlist(id: p.id, name: p.name, coverImgUrl: p.coverImgUrl,
                        description: p.description, creatorName: p.creator?.nickname, tracks: tracks)
    }

    func album(id: Int) async throws -> Album {
        let (data, _) = try await request("/album", query: [URLQueryItem(name: "id", value: String(id))])
        let dec = try JSONDecoder().decode(AlbumResponse.self, from: data)
        guard let a = dec.album else { throw APIError.empty }
        let tracks = (dec.songs ?? []).map { map($0) }
        return Album(id: a.id, name: a.name, coverImgUrl: a.picUrl,
                     artistName: a.artist?.name, tracks: tracks)
    }

    func artistTopSongs(id: Int) async throws -> [Track] {
        let (data, _) = try await request("/artist/top/song", query: [URLQueryItem(name: "id", value: String(id))])
        let dec = try JSONDecoder().decode(ArtistTopResponse.self, from: data)
        return (dec.songs ?? []).map { map($0) }
    }

    func topPlaylists(limit: Int = 30, order: String = "hot") async throws -> [PlaylistBrief] {
        let (data, _) = try await request("/top/playlist", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "order", value: order),
        ])
        let dec = try JSONDecoder().decode(TopPlaylistResponse.self, from: data)
        return (dec.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func login(phone: String, password: String) async throws -> Bool {
        let (data, resp) = try await request("/login/cellphone", method: "POST",
                                             form: ["phone": phone, "password": password])
        if let cookie = resp.allHeaderFields["Set-Cookie"] as? String {
            if let range = cookie.range(of: "MUSIC_U=([^;]+)", options: .regularExpression) {
                let value = String(cookie[range]).replacingOccurrences(of: "MUSIC_U=", with: "")
                AppSettings.shared.musicUCookie = value
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int {
            if code == 200, let acct = json["account"] as? [String: Any], let uid = acct["id"] as? Int {
                AppSettings.shared.userId = uid
            }
            return code == 200
        }
        return true
    }

    func userPlaylists(uid: Int) async throws -> [PlaylistBrief] {
        let (data, _) = try await request("/user/playlist", query: [
            URLQueryItem(name: "uid", value: String(uid)),
            URLQueryItem(name: "limit", value: "100"),
        ])
        let dec = try JSONDecoder().decode(UserPlaylistResponse.self, from: data)
        return (dec.playlist ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: nil)
        }
    }
}
