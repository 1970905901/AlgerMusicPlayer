import SwiftUI
import Kingfisher

struct NowPlayingView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var showLyrics = false

    private let rates: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack {
            backdrop
            VStack(spacing: 0) {
                header
                if showLyrics {
                    LyricsView().environmentObject(player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    artwork
                }
                controls
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let cover = player.currentTrack?.coverURL, let u = URL(string: cover) {
            KFImage(u)
                .resizable()
                .scaledToFill()
                .blur(radius: 40, opaque: true)
                .overlay(Color.black.opacity(0.45))
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title3) }
            Spacer()
            Button { showLyrics.toggle() } label: {
                Image(systemName: showLyrics ? "music.note" : "text.alignleft").font(.title3)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var artwork: some View {
        VStack(spacing: 16) {
            Spacer()
            if let cover = player.currentTrack?.coverURL, let u = URL(string: cover) {
                KFImage(u)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 320)
                    .cornerRadius(16)
                    .shadow(radius: 20)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 280, height: 280)
            }
            VStack(spacing: 4) {
                Text(player.currentTrack?.name ?? "")
                    .font(.title2.bold()).multilineTextAlignment(.center)
                Text(player.currentTrack?.displayArtist ?? "")
                    .font(.subheadline).opacity(0.85)
            }
            Spacer()
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Slider(value: Binding(get: { player.currentTime },
                                  set: { player.seek(to: $0) }),
                   in: 0...max(player.duration, 0.1))
            HStack {
                Text(player.currentTime.mmss).font(.caption2)
                Spacer()
                Text(player.duration.mmss).font(.caption2)
            }
            HStack(spacing: 30) {
                Button { player.cyclePlayMode() } label: {
                    Image(systemName: player.playMode.systemImage)
                }
                Button { player.previous() } label: {
                    Image(systemName: "backward.fill").font(.title)
                }
                Button { player.toggle() } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.fill").font(.title)
                }
                Button { toggleFav() } label: {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                }
            }
            .font(.title3)
            HStack(spacing: 20) {
                Menu {
                    ForEach(rates, id: \.self) { r in
                        Button { player.setRate(r) } label: { Text("\(r, specifier: "%.2g")x") }
                    }
                } label: {
                    Text("\(player.playbackRate, specifier: "%.2g")x")
                        .font(.caption).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.18)).cornerRadius(8)
                }
                Button { if let t = player.currentTrack { library.requestAdd(t) } } label: {
                    Image(systemName: "text.badge.plus")
                }
            }
            .padding(.top, 4)
        }
        .padding(.bottom, 24)
    }

    private var isFav: Bool {
        guard let t = player.currentTrack else { return false }
        return library.isFavorite(t.id)
    }
    private func toggleFav() {
        guard let t = player.currentTrack else { return }
        library.toggleFavorite(t)
    }
}
