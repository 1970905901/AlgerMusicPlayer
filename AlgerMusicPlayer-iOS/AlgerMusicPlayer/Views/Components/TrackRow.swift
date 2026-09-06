import SwiftUI

struct TrackRow: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    let track: Track
    var index: Int = 0
    var onPlay: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            if index > 0 {
                Text("\(index)")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(width: 22, alignment: .center)
            }
            CoverImage(url: track.coverURL, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.name).font(.subheadline).lineLimit(1)
                Text(track.displayArtist).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
            Text(track.duration.mmss).font(.caption).foregroundColor(.secondary)
                .padding(.trailing, 4)
            if library.downloadingIds.contains(track.id) {
                ProgressView().scaleEffect(0.7).padding(.trailing, 2)
            } else if library.isDownloaded(track.id) {
                Image(systemName: "checkmark.circle.fill").font(.caption)
                    .foregroundColor(.accentColor).padding(.trailing, 2)
            }
            Image(systemName: "ellipsis")
                .foregroundColor(.secondary)
                .padding(8)
                .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .onTapGesture { onPlay?() ?? player.playTrack(track) }
        .contextMenu {
            Button { player.playTrack(track) } label: { Label("播放", systemImage: "play") }
            Button {
                library.toggleFavorite(track)
            } label: {
                Label(library.isFavorite(track.id) ? "取消收藏" : "收藏",
                      systemImage: library.isFavorite(track.id) ? "heart.slash" : "heart")
            }
            Button { library.requestAdd(track) } label: { Label("加入歌单", systemImage: "text.badge.plus") }
            if library.isDownloaded(track.id) {
                Button { library.deleteDownload(track.id) } label: { Label("删除下载", systemImage: "trash") }
            } else {
                Button { Task { await library.download(track) } } label: { Label("下载", systemImage: "arrow.down.circle") }
            }
        }
    }
}
