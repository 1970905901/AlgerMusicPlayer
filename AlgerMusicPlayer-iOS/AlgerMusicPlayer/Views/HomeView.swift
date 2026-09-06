import SwiftUI

struct HomeView: View {
    @EnvironmentObject var player: PlayerManager
    @State private var hotPlaylists: [PlaylistBrief] = []
    @State private var loadError: String?
    @State private var path = NavigationPath()

    private let rankings: [(id: Int, name: String)] = [
        (19723756, "飙升榜"), (3779629, "新歌榜"), (3778678, "热歌榜"),
        (2884035, "原创榜"), (1978921795, "云音乐说唱榜"), (713857420, "云音乐电音榜"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let err = loadError {
                        Text("加载失败：\(err)").foregroundColor(.secondary).padding()
                    }
                    section(title: "推荐歌单") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 14) {
                                ForEach(hotPlaylists) { pl in
                                    NavigationLink(value: Route.playlist(pl.id)) {
                                        PlaylistCard(playlist: pl)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    section(title: "排行榜") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 14) {
                            ForEach(rankings, id: \.id) { r in
                                NavigationLink(value: Route.playlist(r.id)) {
                                    HStack {
                                        Image(systemName: "chart.line.uptrend.xyaxis")
                                            .foregroundColor(.accentColor)
                                        Text(r.name).font(.subheadline.bold())
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary).font(.caption)
                                    }
                                    .padding(14)
                                    .background(Color(.secondarySystemFill))
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("发现音乐")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .playlist(let id): PlaylistDetailView(id: id)
                case .album(let id): AlbumDetailView(id: id)
                case .artist(let id): ArtistDetailView(id: id)
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold()).padding(.horizontal, 16)
            content()
        }
    }

    private func load() async {
        do {
            let lists = try await NeteaseAPI.shared.topPlaylists(limit: 20)
            await MainActor.run {
                self.hotPlaylists = lists
                self.loadError = nil
            }
        } catch {
            await MainActor.run { self.loadError = error.localizedDescription }
        }
    }
}
