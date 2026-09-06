import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject var player: PlayerManager
    var body: some View {
        HStack(spacing: 12) {
            CoverImage(url: player.currentTrack?.coverURL, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.name ?? "")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(player.currentTrack?.displayArtist ?? "")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 4)
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .padding(.trailing, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
