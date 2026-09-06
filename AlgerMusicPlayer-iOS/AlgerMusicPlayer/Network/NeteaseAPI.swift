import Foundation
import CommonCrypto
import CryptoKit

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

/// Client-side NetEase Cloud Music request signing (weapi / eapi).
///
/// - weapi: two AES-128-CBC passes over the JSON — first with a preset key,
///   then with a client-chosen secret key. The secret key is normally
///   RSA-encrypted per request; since we choose it, we ship a fixed key with
///   its RSA ciphertext precomputed (verified against the `kumone` project),
///   avoiding a BigInt implementation on the client.
/// - eapi: AES-128-ECB over "url + payload + md5 digest" with a fixed key.
enum NeteaseCrypto {
    private static let weapiPresetKey = "0CoJUm6Qyw8W8jud"
    private static let weapiIV = "0102030405060708"
    private static let weapiSecretKey = "kumone2026abcDEF"
    private static let weapiEncSecKey =
        "38cef2efdbcc1cfd6a44d81620dae5d23091f50ef27e01a1b1bb7e998e0fde2d" +
        "7ab6002a9e79a3c195f661cbde80e21e6245997b11b54d28407115822f95d447" +
        "7cc06b5a77de46fab6568410abf1229abef81b4c8588f386149010d190bb0b04" +
        "f064be330bd877a4d4b99514febbdb4335b10744b13d9f7ee24d314d6e62cdc9"
    private static let eapiKey = "e82ckenh8dichen8"

    /// Encrypt a JSON payload for a `/weapi/...` endpoint. Returns form fields.
    static func weapi(payload: Data) -> [String: String] {
        let first = aes128(payload, key: weapiPresetKey, cbcIV: weapiIV)
        let firstB64 = first.base64EncodedString()
        let second = aes128(Data(firstB64.utf8), key: weapiSecretKey, cbcIV: weapiIV)
        return ["params": second.base64EncodedString(), "encSecKey": weapiEncSecKey]
    }

    /// Encrypt a JSON payload for an `/eapi/...` endpoint.
    /// - Parameter apiPath: the internal API path, e.g. "/api/song/enhance/player/url/v1"
    static func eapi(apiPath: String, payload: Data) -> [String: String] {
        let text = String(decoding: payload, as: UTF8.self)
        let message = "nobody\(apiPath)use\(text)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let body = "\(apiPath)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"
        let encrypted = aes128(Data(body.utf8), key: eapiKey, cbcIV: nil)
        return ["params": encrypted.map { String(format: "%02X", $0) }.joined()]
    }

    /// NetEase expects the login password as an MD5 hex digest.
    static func md5(_ s: String) -> String {
        Insecure.MD5.hash(data: Data(s.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// AES-128 with PKCS7 padding. CBC when `cbcIV` is given, ECB otherwise.
    private static func aes128(_ data: Data, key: String, cbcIV: String?) -> Data {
        let keyData = Data(key.utf8)
        var out = Data(count: data.count + kCCBlockSizeAES128)
        var written = 0
        let options: CCOptions = cbcIV == nil
            ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)
            : CCOptions(kCCOptionPKCS7Padding)
        let ivData = cbcIV.map { Data($0.utf8) }
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                keyData.withUnsafeBytes { keyPtr in
                    if let ivData {
                        return ivData.withUnsafeBytes { ivPtr in
                            CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                    options, keyPtr.baseAddress, keyData.count, ivPtr.baseAddress,
                                    dataPtr.baseAddress, data.count,
                                    outPtr.baseAddress, outPtr.count, &written)
                        }
                    } else {
                        return CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES),
                                       options, keyPtr.baseAddress, keyData.count, nil,
                                       dataPtr.baseAddress, data.count,
                                       outPtr.baseAddress, outPtr.count, &written)
                    }
                }
            }
        }
        precondition(status == kCCSuccess, "AES encryption failed: \(status)")
        return out.prefix(written)
    }
}

/// Thin async client that signs and calls NetEase Cloud Music's official
/// `weapi` / `eapi` endpoints directly — no third-party backend required.
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

    private var cookieHeaderValue: String {
        get async {
            let c = await AppSettings.shared.musicUCookie
            return c.isEmpty ? "" : "MUSIC_U=\(c)"
        }
    }

    /// Percent-encode form values (base64 `params` contains `+`, `/`, `=` that
    /// would otherwise be mangled by the server's form parser).
    private func encodeForm(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }

    /// POST a signed `weapi` request to `https://music.163.com/weapi<path>`.
    private func weapi(_ path: String, _ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        var body = payload
        body["csrf_token"] = ""
        guard let json = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://music.163.com/weapi\(path)") else {
            throw APIError.invalidResponse
        }
        let form = NeteaseCrypto.weapi(payload: json)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var cookie = await cookieHeaderValue
        if !cookie.isEmpty { cookie += "; " }
        cookie += "os=pc; appver=3.1.17"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.httpBody = encodeForm(form)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 { throw APIError.invalidResponse }
        return (data, http)
    }

    /// POST a signed `eapi` request to `https://interface.music.163.com/eapi<path>`.
    private func eapi(_ path: String, _ payload: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        let apiPath = "/api" + path
        var body = payload
        var header: [String: Any] = [
            "os": "pc", "appver": "3.1.17",
            "osver": "Version 14.0 (Build 23A344)", "deviceId": "alger",
            "requestId": String(Int.random(in: 20_000_000...30_000_000)),
            "clientSign": "", "versioncode": "140",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "resolution": "1920x1080", "channel": ""
        ]
        let musicU = await AppSettings.shared.musicUCookie
        if !musicU.isEmpty { header["MUSIC_U"] = musicU }
        body["header"] = header
        guard let json = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://interface.music.163.com/eapi\(path)") else {
            throw APIError.invalidResponse
        }
        let form = NeteaseCrypto.eapi(apiPath: apiPath, payload: json)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var cookie = await cookieHeaderValue
        if !cookie.isEmpty { cookie += "; " }
        cookie += "os=pc; appver=3.1.17"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.httpBody = encodeForm(form)
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
        let (data, _) = try await weapi("/search/get", [
            "keywords": keyword, "type": 1, "limit": limit, "offset": offset
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.songs ?? []).map { map($0) }
    }

    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [AlbumBrief] {
        let (data, _) = try await weapi("/search/get", [
            "keywords": keyword, "type": 10, "limit": limit
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.albums ?? []).map {
            AlbumBrief(id: $0.id, name: $0.name, coverImgUrl: $0.picUrl, artistName: $0.artist?.name)
        }
    }

    func searchPlaylists(keyword: String, limit: Int = 30) async throws -> [PlaylistBrief] {
        let (data, _) = try await weapi("/search/get", [
            "keywords": keyword, "type": 1000, "limit": limit
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func searchArtists(keyword: String, limit: Int = 30) async throws -> [ArtistBrief] {
        let (data, _) = try await weapi("/search/get", [
            "keywords": keyword, "type": 100, "limit": limit
        ])
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (dec.result?.artists ?? []).map {
            ArtistBrief(id: $0.id, name: $0.name, coverURL: $0.picUrl ?? $0.img1v1Url)
        }
    }

    func songURL(id: Int, level: String = "standard") async throws -> String? {
        let (data, _) = try await eapi("/song/enhance/player/url/v1", [
            "ids": "[\(id)]", "level": level, "encodeType": "flac"
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
        let (data, _) = try await weapi("/song/lyric", ["id": id])
        let dec = try JSONDecoder().decode(LyricResponse.self, from: data)
        return (dec.lrc?.lyric ?? "", dec.tlyric?.lyric ?? "")
    }

    func playlistDetail(id: Int) async throws -> Playlist {
        let (data, _) = try await weapi("/v3/playlist/detail", ["id": id, "n": 1000])
        let dec = try JSONDecoder().decode(PlaylistDetailResponse.self, from: data)
        guard let p = dec.playlist else { throw APIError.empty }
        let tracks = (p.tracks ?? []).map { map($0) }
        return Playlist(id: p.id, name: p.name, coverImgUrl: p.coverImgUrl,
                        description: p.description, creatorName: p.creator?.nickname, tracks: tracks)
    }

    func album(id: Int) async throws -> Album {
        let (data, _) = try await weapi("/v1/album", ["id": id])
        let dec = try JSONDecoder().decode(AlbumResponse.self, from: data)
        guard let a = dec.album else { throw APIError.empty }
        let tracks = (dec.songs ?? []).map { map($0) }
        return Album(id: a.id, name: a.name, coverImgUrl: a.picUrl,
                     artistName: a.artist?.name, tracks: tracks)
    }

    func artistTopSongs(id: Int) async throws -> [Track] {
        let (data, _) = try await weapi("/artist/top/song", ["id": id])
        let dec = try JSONDecoder().decode(ArtistTopResponse.self, from: data)
        return (dec.songs ?? []).map { map($0) }
    }

    func topPlaylists(limit: Int = 30, order: String = "hot") async throws -> [PlaylistBrief] {
        let (data, _) = try await weapi("/playlist/highquality/list", [
            "limit": limit, "order": order
        ])
        let dec = try JSONDecoder().decode(TopPlaylistResponse.self, from: data)
        return (dec.playlists ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: $0.playCount)
        }
    }

    func login(phone: String, password: String) async throws -> Bool {
        let (data, resp) = try await weapi("/w/login/cellphone", [
            "phone": phone, "password": NeteaseCrypto.md5(password)
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
        let (data, _) = try await weapi("/user/playlist", [
            "uid": uid, "limit": 1000, "offset": 0
        ])
        let dec = try JSONDecoder().decode(UserPlaylistResponse.self, from: data)
        return (dec.playlist ?? []).map {
            PlaylistBrief(id: $0.id, name: $0.name, coverImgUrl: $0.coverImgUrl,
                          description: $0.description, trackCount: $0.trackCount ?? 0,
                          creatorName: $0.creator?.nickname, playCount: nil)
        }
    }
}
