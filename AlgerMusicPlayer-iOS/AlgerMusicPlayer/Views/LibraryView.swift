import SwiftUI
import Combine

struct LibraryView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    @State private var cloudPlaylists: [PlaylistBrief] = []
    @State private var showCreate = false
    @State private var newName = ""

    private var loggedIn: Bool { !AppSettings.shared.musicUCookie.isEmpty && AppSettings.shared.userId != 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        DownloadedView().environmentObject(player).environmentObject(library)
                    } label: {
                        Label("已下载", systemImage: "arrow.down.circle.fill").foregroundColor(.blue)
                    }
                }
                Section {
                    NavigationLink {
                        FavoritesView().environmentObject(player).environmentObject(library)
                    } label: {
                        Label("我喜欢的音乐", systemImage: "heart.fill").foregroundColor(.pink)
                    }
                    if loggedIn {
                        NavigationLink {
                            CloudPlaylistsView(playlists: $cloudPlaylists).environmentObject(player)
                        } label: {
                            Label("云端歌单", systemImage: "icloud.fill")
                        }
                        .task { await loadCloud() }
                    }
                }
                Section {
                    ForEach(library.playlists) { pl in
                        NavigationLink {
                            LocalPlaylistView(playlist: pl)
                                .environmentObject(player)
                                .environmentObject(library)
                        } label: {
                            HStack(spacing: 12) {
                                CoverImage(url: nil, size: 44)
                                VStack(alignment: .leading) {
                                    Text(pl.name).font(.subheadline)
                                    Text("\(pl.tracks.count) 首").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { idx in
                        idx.forEach { library.deletePlaylist(library.playlists[$0].id) }
                    }
                    Button { showCreate = true } label: {
                        Label("新建歌单", systemImage: "plus.circle")
                    }
                } header: { Text("我的歌单") }
            }
            .navigationTitle("音乐库")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                }
            }
            .alert("新建歌单", isPresented: $showCreate) {
                TextField("歌单名称", text: $newName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    library.createPlaylist(name: newName.isEmpty ? "我的歌单" : newName)
                    newName = ""
                }
            }
        }
    }

    private func loadCloud() async {
        let uid = AppSettings.shared.userId
        guard uid != 0 else { return }
        do {
            let r = try await NeteaseAPI.shared.userPlaylists(uid: uid)
            await MainActor.run { cloudPlaylists = r }
        } catch {
            // ignore cloud errors
        }
    }
}

struct FavoritesView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        List {
            if library.favorites.isEmpty {
                Text("还没有收藏的歌曲").foregroundColor(.secondary)
            }
            ForEach(Array(library.favorites.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t.track, index: i + 1) {
                    player.playQueue(library.favorites.map { $0.track }, startAt: i)
                }
                .environmentObject(player)
                .environmentObject(library)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle("我喜欢的音乐")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { player.playQueue(library.favorites.map { $0.track }) } label: {
                    Image(systemName: "play.fill")
                }
            }
        }
    }
}

struct DownloadedView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    var body: some View {
        List {
            if library.downloaded.isEmpty {
                Text("还没有下载的歌曲").foregroundColor(.secondary)
            }
            ForEach(Array(library.downloaded.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t.track, index: i + 1) {
                    player.playQueue(library.downloaded.map { $0.track }, startAt: i)
                }
                .environmentObject(player)
                .environmentObject(library)
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(role: .destructive) { library.deleteDownload(t.id) } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("已下载")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { player.playQueue(library.downloaded.map { $0.track }) } label: {
                    Image(systemName: "play.fill")
                }
            }
        }
    }
}

struct CloudPlaylistsView: View {
    @EnvironmentObject var player: PlayerManager
    @Binding var playlists: [PlaylistBrief]
    var body: some View {
        List(playlists) { p in
            NavigationLink(value: Route.playlist(p.id)) {
                HStack(spacing: 12) {
                    CoverImage(url: p.coverImgUrl, size: 48)
                    VStack(alignment: .leading) {
                        Text(p.name).font(.subheadline)
                        if let c = p.creatorName { Text(c).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .playlist(let id): PlaylistDetailView(id: id)
                default: EmptyView()
                }
            }
        }
        .navigationTitle("云端歌单")
    }
}

struct LocalPlaylistView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    @State var playlist: LocalPlaylist
    var body: some View {
        List {
            ForEach(Array(playlist.tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t.track, index: i + 1) {
                    player.playQueue(playlist.tracks.map { $0.track }, startAt: i)
                }
                .environmentObject(player)
                .environmentObject(library)
                .listRowSeparator(.hidden)
                .swipeActions {
                    Button(role: .destructive) {
                        library.remove(t.id, from: playlist.id)
                    } label: { Label("删除", systemImage: "trash") }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(playlist.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { player.playQueue(playlist.tracks.map { $0.track }) } label: {
                    Image(systemName: "play.fill")
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button { library.deletePlaylist(playlist.id) } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onReceive(library.$playlists) { all in
            if let updated = all.first(where: { $0.id == playlist.id }) {
                playlist = updated
            }
        }
    }
}
