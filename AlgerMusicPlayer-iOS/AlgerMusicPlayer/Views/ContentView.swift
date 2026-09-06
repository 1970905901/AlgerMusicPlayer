import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, search, library, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "首页"
        case .search: return "搜索"
        case .library: return "音乐库"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .home: return "house"
        case .search: return "magnifyingglass"
        case .library: return "music.note.list"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var player: PlayerManager
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var selectedTab: Tab = .home
    @State private var showNowPlaying = false

    private var isIPad: Bool { hSize == .regular }

    var body: some View {
        Group {
            if isIPad { iPadLayout } else { iPhoneLayout }
        }
        .preferredColorScheme(colorScheme)
        .fullScreenCover(isPresented: $showNowPlaying) {
            if player.currentTrack != nil {
                NowPlayingView().environmentObject(player)
            }
        }
        .sheet(item: $library.pendingAddTrack) { track in
            AddToPlaylistSheet(track: track).environmentObject(library)
        }
    }

    private var colorScheme: ColorScheme? {
        switch settings.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var iPhoneLayout: some View {
        VStack(spacing: 0) {
            ZStack {
                switch selectedTab {
                case .home: HomeView()
                case .search: SearchView()
                case .library: LibraryView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if player.currentTrack != nil {
                MiniPlayer()
                    .contentShape(Rectangle())
                    .onTapGesture { showNowPlaying = true }
            }
            CustomTabBar(selected: $selectedTab)
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: Binding(
                get: { selectedTab },
                set: { if let t = $0 { selectedTab = t } }
            )) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
            .navigationTitle("AlgerMusic")
        } detail: {
            VStack(spacing: 0) {
                ZStack {
                    switch selectedTab {
                    case .home: HomeView()
                    case .search: SearchView()
                    case .library: LibraryView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if player.currentTrack != nil {
                    MiniPlayer()
                        .contentShape(Rectangle())
                        .onTapGesture { showNowPlaying = true }
                }
            }
        }
    }
}
