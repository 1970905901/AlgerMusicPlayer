import Foundation
import CommonCrypto

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

/// Client-side NetEase Cloud Music `weapi` request signing. The official API
/// requires AES-128-CBC encrypted `params`/`encSecKey`; historically a proxy
/// (`netease-cloud-music-api-alger`) did this server-side. We now sign locally
/// and talk to `music.163.com` directly, so no third-party backend is needed.
enum NeteaseCrypto {
    // First AES pass key (fixed by NetEase) and CBC IV.
    private static let firstKey = "0CoJUm6Qyw8W8jud"
    private static let iv = "0102030405060708"
    // Per-client secretKey (16 bytes) and its precomputed encSecKey
    // (secretKey reversed → big-endian int, then ^65537 mod n). Computed once
    // offline; a fixed pair is what many official/third-party clients use.
    private static let secretKey = "abcdefghijklmnop"
    private static let encSecKey = "3177e70615c10d79eca876c985040d6a5f6af70ca834c1404edc94032f59cfff0fecf03d1d56f03d010ba66d2a931ec7519bc26fe836f9c63bcea0e40e116f07c8c57da0e0e9a5f91a4aedec564521228045c0a221417034f13eff1a07257af27859936ca73cf92eabc98491955d54ad908948f993d0b83a658e1cc95a59f246"

    /// AES-128-CBC with PKCS7 padding (handled by CommonCrypto), base64 output.
    static func aesEncrypt(_ plainText: String, key: String) -> String? {
        guard let keyData = key.data(using: .utf8), keyData.count == 16,
              let data = plainText.data(using: .utf8) else { return nil }
        let ivData = Data(iv.utf8)
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var numBytes: size_t = 0
        let status = out.withUnsafeMutableBytes { ob in
            data.withUnsafeBytes { db in
                ivData.withUnsafeBytes { ib in
                    keyData.withUnsafeBytes { kb in
                        CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                kb.baseAddress, kCCKeySizeAES128, ib.baseAddress,
                                db.baseAddress, data.count,
                                ob.baseAddress, out.count, &numBytes)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return out.prefix(numBytes).base64EncodedString()
    }

    /// Encrypt a JSON payload into the `params`/`encSecKey` pair NetEase expects.
    static func encrypt(_ payload: [String: Any]) -> (params: String, encSecKey: String)? {
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let jsonStr = String(data: json, encoding: .utf8),
              let first = aesEncrypt(jsonStr, key: firstKey),
              let second = aesEncrypt(first, key: secretKey) else { return nil }
        return (second, encSecKey)
    }

    /// NetEase expects the login password as an MD5 hex digest.
    static func md5(_ s: String) -> String {
        let data = Data(s.utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { db in
            digest.withUnsafeMutableBytes { mb in
                CC_MD5(db.baseAddress, CC_LONG(data.count), mb.bindMemory(to: UInt8.self).baseAddress)
            }
        }
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Thin async client that signs and calls NetEase Cloud Music's official
/// `weapi` endpoints directly.
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
        get async {
            let raw = await AppSettings.shared.apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmed = raw.isEmpty ? "https://music.163.com" : raw
            return trimmed.last == "/" ? String(trimmed.dropLast()) : trimmed
        }
    }

    private var cookieHeader: String? {
        get async {
            let c = await AppSettings.shared.musicUCookie
            return c.isEmpty ? nil : "MUSIC_U=\(c)"
        }
    }

    /// Perform a signed `weapi` POST to `path` (e.g. "/weapi/search/get").
    private func weapi(_ path: String, _ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let (params, encSecKey) = NeteaseCrypto.encrypt(payload),
              let url = URL(string: await baseURL + path) else {
            throw APIError.invalidResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        if let c = await cookieHeader { req.setValue(c, forHTTPHeaderField: "Cookie") }
        req.httpBody = "params=\(params)&encSecKey=\(encSecKey)".data(using: .utf8)
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
        let (data, _) = try await weapi("/weapi/search/get", [
            "keywords": keyword, "type": 1, "limit": limit, "offset": offset, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.songs ?? []).map { map($0) }
    }

    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [AlbumBrief] {
        let (data, _) = try await weapi("/weapi/search/get", [
            "keywords": keyword, "type": 10, "limit": limit, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.albums ?? []).map {
            AlbumBrief(id: $0.id, name: $0.name, coverImgUrl: $0.picUrl, artistName: $0.artist?.name)
        }
    }

    func searchPlaylists(keyword: String, limit: Int = 30) async throws -> [PlaylistBrief] {
        let (data, _) = try await weapi("/weapi/search/get", [
            "keywords": keyword, "type": 1000, "limit": limit, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func searchArtists(keyword: String, limit: Int = 30) async throws -> [ArtistBrief] {
        let (data, _) = try await weapi("/weapi/search/get", [
            "keywords": keyword, "type": 100, "limit": limit, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.artists ?? []).map {
            ArtistBrief(id: $0.id, name: $0.name, coverURL: $0.picUrl ?? $0.img1v1Url)
        }
    }

    func songURL(id: Int, level: String = "standard") async throws -> String? {
        let (data, _) = try await weapi("/weapi/song/enhance/player/url/v1", [
            "id": id, "level": level, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(SongURLResponse.self, from: data)
        return dec.data?.first?.url
    }

    /// Download the raw audio data for a track (used for offline playback).
    func download(id: Int) async throws -> Data {
        guard let urlStr = try await songURL(id: id, level: await AppSettings.shared.audioQuality.rawValue),
              let u = URL(string: urlStr) else { throw APIError.empty }
        let (data, _) = try await session.data(from: u)
        return data
    }

    func lyric(id: Int) async throws -> (String, String) {
        let (data, _) = try await weapi("/weapi/song/lyric", ["id": id, "csrf_token": ""])
        let dec = try JSONDecoder().decode(LyricResponse.self, from: data)
        return (dec.lrc?.lyric ?? "", dec.tlyric?.lyric ?? "")
    }

    func playlistDetail(id: Int) async throws -> Playlist {
        let (data, _) = try await weapi("/weapi/v3/playlist/detail", [
            "id": id, "n": 1000, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(PlaylistDetailResponse.self, from: data)
        guard let p = dec.playlist else { throw APIError.empty }
        let tracks = (p.tracks ?? []).map { map($0) }
        return Playlist(id: p.id, name: p.name, coverImgUrl: p.coverImgUrl,
                        description: p.description, creatorName: p.creator?.nickname, tracks: tracks)
    }

    func album(id: Int) async throws -> Album {
        let (data, _) = try await weapi("/weapi/v1/album", ["id": id, "csrf_token": ""])
        let dec = try JSONDecoder().decode(AlbumResponse.self, from: data)
        guard let a = dec.album else { throw APIError.empty }
        let tracks = (dec.songs ?? []).map { map($0) }
        return Album(id: a.id, name: a.name, coverImgUrl: a.picUrl,
                     artistName: a.artist?.name, tracks: tracks)
    }

    func artistTopSongs(id: Int) async throws -> [Track] {
        let (data, _) = try await weapi("/weapi/artist/top/song", ["id": id, "csrf_token": ""])
        let dec = try JSONDecoder().decode(ArtistTopResponse.self, from: data)
        return (dec.songs ?? []).map { map($0) }
    }

    func topPlaylists(limit: Int = 30, order: String = "hot") async throws -> [PlaylistBrief] {
        let (data, _) = try await weapi("/weapi/playlist/highquality/list", [
            "limit": limit, "order": order, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(TopPlaylistResponse.self, from: data)
        return (dec.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func login(phone: String, password: String) async throws -> Bool {
        let (data, resp) = try await weapi("/weapi/login/cellphone", [
            "phone": phone, "password": NeteaseCrypto.md5(password), "csrf_token": ""
        ])
        if let cookie = resp.allHeaderFields["Set-Cookie"] as? String {
            if let range = cookie.range(of: "MUSIC_U=([^;]+)", options: .regularExpression) {
                let value = String(cookie[range]).replacingOccurrences(of: "MUSIC_U=", with: "")
                await MainActor.run { AppSettings.shared.musicUCookie = value }
            }
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = json["code"] as? Int {
            if code == 200, let acct = json["account"] as? [String: Any], let uid = acct["id"] as? Int {
                await MainActor.run { AppSettings.shared.userId = uid }
            }
            return code == 200
        }
        return true
    }

    func userPlaylists(uid: Int) async throws -> [PlaylistBrief] {
        let (data, _) = try await weapi("/weapi/user/playlist", [
            "uid": uid, "limit": 1000, "offset": 0, "csrf_token": ""
        ])
        let dec = try JSONDecoder().decode(UserPlaylistResponse.self, from: data)
        return (dec.playlist ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: nil)
        }
    }
}
