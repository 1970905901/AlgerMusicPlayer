import SwiftUI

struct PlaylistDetailView: View {
    @EnvironmentObject var player: PlayerManager
    @State private var playlist: Playlist?
    @State private var loading = true
    @State private var errorMsg: String?
    let id: Int

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let pl = playlist {
                content(pl)
            } else {
                Text(errorMsg ?? "加载失败").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(playlist?.name ?? "歌单")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ pl: Playlist) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CoverImage(url: pl.coverImgUrl, size: 96, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pl.name).font(.title3.bold())
                        if let d = pl.description, !d.isEmpty {
                            Text(d).font(.caption).foregroundColor(.secondary).lineLimit(3)
                        }
                        if let c = pl.creatorName {
                            Text("by \(c)").font(.caption).foregroundColor(.secondary)
                        }
                        Button { player.playQueue(pl.tracks) } label: {
                            Label("播放全部", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(Array(pl.tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, index: i + 1) { player.playQueue(pl.tracks, startAt: i) }
                    .environmentObject(player)
                    .environmentObject(LibraryStore.shared)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func load() async {
        do {
            let pl = try await NeteaseAPI.shared.playlistDetail(id: id)
            await MainActor.run { playlist = pl; loading = false }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; loading = false }
        }
    }
}

struct AlbumDetailView: View {
    @EnvironmentObject var player: PlayerManager
    @State private var album: Album?
    @State private var loading = true
    @State private var errorMsg: String?
    let id: Int

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let al = album {
                albumContent(al)
            } else {
                Text(errorMsg ?? "加载失败").foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(album?.name ?? "专辑")
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    @ViewBuilder
    private func albumContent(_ al: Album) -> some View {
        List {
            Section {
                HStack(spacing: 14) {
                    CoverImage(url: al.coverImgUrl, size: 96, cornerRadius: 12)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(al.name).font(.title3.bold())
                        if let ar = al.artistName {
                            Text(ar).font(.caption).foregroundColor(.secondary)
                        }
                        Button { player.playQueue(al.tracks) } label: {
                            Label("播放全部", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(Array(al.tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, index: i + 1) { player.playQueue(al.tracks, startAt: i) }
                    .environmentObject(player)
                    .environmentObject(LibraryStore.shared)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private func load() async {
        do {
            let al = try await NeteaseAPI.shared.album(id: id)
            await MainActor.run { album = al; loading = false }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; loading = false }
        }
    }
}

struct ArtistDetailView: View {
    @EnvironmentObject var player: PlayerManager
    @State private var tracks: [Track] = []
    @State private var name: String = ""
    @State private var loading = true
    @State private var errorMsg: String?
    let id: Int

    var body: some View {
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                        TrackRow(track: t, index: i + 1) { player.playQueue(tracks, startAt: i) }
                            .environmentObject(player)
                            .environmentObject(LibraryStore.shared)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(name.isEmpty ? "歌手" : name)
        .navigationBarTitleDisplayMode(.large)
        .task { await load() }
    }

    private func load() async {
        do {
            let r = try await NeteaseAPI.shared.artistTopSongs(id: id)
            await MainActor.run { tracks = r; loading = false }
        } catch {
            await MainActor.run { errorMsg = error.localizedDescription; loading = false }
        }
    }
}
