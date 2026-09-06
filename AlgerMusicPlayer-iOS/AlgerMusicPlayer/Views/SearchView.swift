import SwiftUI

struct SearchView: View {
    @EnvironmentObject var player: PlayerManager
    @State private var query = ""
    @State private var songs: [Track] = []
    @State private var albums: [AlbumBrief] = []
    @State private var playlists: [PlaylistBrief] = []
    @State private var artists: [ArtistBrief] = []
    @State private var scope: SearchScope = .song
    @State private var searching = false
    @State private var errorMsg: String?
    @State private var path = NavigationPath()

    enum SearchScope: String, CaseIterable, Identifiable {
        case song, album, playlist, artist
        var id: String { rawValue }
        var title: String {
            switch self {
            case .song: return "单曲"
            case .album: return "专辑"
            case .playlist: return "歌单"
            case .artist: return "歌手"
            }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                Picker("类型", selection: $scope) {
                    ForEach(SearchScope.allCases) { s in Text(s.title).tag(s) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                contentList
            }
            .navigationTitle("搜索")
            .searchable(text: $query, prompt: "歌曲、歌手、专辑、歌单")
            .autocapitalization(.none)
            .onSubmit(of: .search) { Task { await runSearch() } }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .playlist(let id): PlaylistDetailView(id: id)
                case .album(let id): AlbumDetailView(id: id)
                case .artist(let id): ArtistDetailView(id: id)
                }
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if searching {
            ProgressView("搜索中…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMsg, !query.isEmpty {
            Text("出错：\(err)").foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.isEmpty {
            emptyHint
        } else {
            List {
                switch scope {
                case .song:
                    ForEach(Array(songs.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, index: i + 1) { player.playQueue(songs, startAt: i) }
                            .environmentObject(player)
                            .environmentObject(LibraryStore.shared)
                            .listRowSeparator(.hidden)
                    }
                case .album:
                    ForEach(albums) { a in
                        NavigationLink(value: Route.album(a.id)) {
                            HStack(spacing: 12) {
                                CoverImage(url: a.coverImgUrl, size: 48)
                                VStack(alignment: .leading) {
                                    Text(a.name).font(.subheadline)
                                    if let ar = a.artistName {
                                        Text(ar).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case .playlist:
                    ForEach(playlists) { p in
                        NavigationLink(value: Route.playlist(p.id)) {
                            HStack(spacing: 12) {
                                CoverImage(url: p.coverImgUrl, size: 48)
                                VStack(alignment: .leading) {
                                    Text(p.name).font(.subheadline)
                                    if let c = p.creatorName {
                                        Text(c).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                case .artist:
                    ForEach(artists) { ar in
                        NavigationLink(value: Route.artist(ar.id)) {
                            HStack(spacing: 12) {
                                CoverImage(url: ar.coverURL, size: 48)
                                Text(ar.name).font(.subheadline)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
            Text("搜索你喜欢的音乐").foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        await MainActor.run { searching = true; errorMsg = nil }
        do {
            switch scope {
            case .song:
                let r = try await NeteaseAPI.shared.searchSongs(keyword: q)
                await MainActor.run { songs = r }
            case .album:
                let r = try await NeteaseAPI.shared.searchAlbums(keyword: q)
                await MainActor.run { albums = r }
            case .playlist:
                let r = try await NeteaseAPI.shared.searchPlaylists(keyword: q)
                await MainActor.run { playlists = r }
            case .artist:
                let r = try await NeteaseAPI.shared.searchArtists(keyword: q)
                await MainActor.run { artists = r }
            }
            await MainActor.run { searching = false }
        } catch {
            await MainActor.run { searching = false; errorMsg = error.localizedDescription }
        }
    }
}
