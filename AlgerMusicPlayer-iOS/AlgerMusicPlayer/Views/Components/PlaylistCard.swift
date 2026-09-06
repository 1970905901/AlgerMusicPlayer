import SwiftUI

struct PlaylistCard: View {
    let playlist: PlaylistBrief
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: playlist.coverImgUrl, size: 150, cornerRadius: 10)
                .frame(width: 150)
            Text(playlist.name)
                .font(.subheadline.bold())
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)
            if let c = playlist.creatorName {
                Text(c)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 150, alignment: .leading)
            }
        }
        .frame(width: 150)
    }
}
