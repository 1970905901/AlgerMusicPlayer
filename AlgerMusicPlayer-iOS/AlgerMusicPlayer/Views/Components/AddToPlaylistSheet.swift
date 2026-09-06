import SwiftUI

struct AddToPlaylistSheet: View {
    @EnvironmentObject var library: LibraryStore
    let track: Track
    @State private var newName = ""
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("新建歌单") {
                    HStack {
                        TextField("歌单名称", text: $newName)
                        Button("创建并加入") {
                            let name = newName.isEmpty ? "我的歌单" : newName
                            let pl = library.createPlaylist(name: name)
                            library.add(track, to: pl.id)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Section("我的歌单") {
                    if library.playlists.isEmpty {
                        Text("暂无歌单").foregroundColor(.secondary)
                    }
                    ForEach(library.playlists) { pl in
                        Button {
                            library.add(track, to: pl.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(pl.name)
                                Spacer()
                                Text("\(pl.tracks.count)").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入歌单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
