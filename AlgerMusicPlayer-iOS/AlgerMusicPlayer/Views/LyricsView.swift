import SwiftUI

struct LyricsView: View {
    @EnvironmentObject var player: PlayerManager
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if player.lyricLines.isEmpty {
                    Text(player.lyricLoadFailed ? "暂无歌词" : "歌词加载中…")
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 220)
                        .frame(maxWidth: .infinity)
                } else {
                    VStack(spacing: 18) {
                        let idx = player.currentLyricIndex
                        ForEach(Array(player.lyricLines.enumerated()), id: \.element.id) { i, line in
                            Text(line.text)
                                .font(idx == i ? .title3.bold() : .body)
                                .foregroundColor(idx == i ? .white : .white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .id(i)
                                .onTapGesture { player.seek(to: line.time) }
                        }
                        Spacer().frame(height: 200)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .onChange(of: player.currentLyricIndex) { i in
                withAnimation { proxy.scrollTo(i, anchor: .center) }
            }
            .onAppear {
                withAnimation { proxy.scrollTo(player.currentLyricIndex, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
