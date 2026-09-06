import SwiftUI
import Kingfisher

/// Async cover-art image with a placeholder, backed by Kingfisher.
struct CoverImage: View {
    let url: String?
    var size: CGFloat = 56
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let url, let u = URL(string: url) {
                KFImage(u)
                    .placeholder { Color(.secondarySystemFill) }
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: size, height: size)
                    .cornerRadius(cornerRadius)
                    .clipped()
            } else {
                Color(.secondarySystemFill)
                    .frame(width: size, height: size)
                    .cornerRadius(cornerRadius)
            }
        }
    }
}
