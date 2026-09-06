import SwiftUI

@main
struct AlgerMusicPlayerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PlayerManager.shared)
                .environmentObject(LibraryStore.shared)
                .environmentObject(AppSettings.shared)
        }
    }
}
