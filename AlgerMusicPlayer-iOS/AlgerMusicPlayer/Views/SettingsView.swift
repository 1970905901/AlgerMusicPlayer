import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var player: PlayerManager
    @State private var phone = ""
    @State private var password = ""
    @State private var loginMsg: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("API 服务") {
                    TextField("API 服务器地址", text: $settings.apiBaseURL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("指向一个 netease-cloud-music-api-alger 实例，例如 http://192.168.1.10:3000 或你的部署地址")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section("播放") {
                    Picker("音质", selection: $settings.audioQuality) {
                        ForEach(AudioQuality.allCases) { q in Text(q.label).tag(q) }
                    }
                    Picker("主题", selection: $settings.themeMode) {
                        ForEach(ThemeMode.allCases) { t in Text(t.label).tag(t) }
                    }
                    Stepper("倍速 \(settings.playbackRate, specifier: "%.2g")x",
                            value: $settings.playbackRate, in: 0.5...2.0, step: 0.25)
                        .onChange(of: settings.playbackRate) { rate in
                            player.setRate(rate)
                        }
                }
                Section("账号") {
                    if settings.userId != 0 {
                        Text("已登录（UID \(settings.userId)）").foregroundColor(.secondary)
                        Button("退出登录") {
                            settings.musicUCookie = ""
                            settings.userId = 0
                        }
                    } else {
                        TextField("手机号", text: $phone)
                            .keyboardType(.phonePad)
                        SecureField("密码", text: $password)
                        Button { Task { await login() } } label: { Text("登录") }
                        if let m = loginMsg {
                            Text(m).font(.caption).foregroundColor(.secondary)
                        }
                        Text("登录用于同步云端歌单，本地播放无需登录")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }
                Section("关于") {
                    HStack { Text("版本"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
                    Link("项目主页", destination: URL(string: "https://github.com/1970905901/AlgerMusicPlayer")!)
                }
            }
            .navigationTitle("设置")
        }
    }

    private func login() async {
        guard !phone.isEmpty, !password.isEmpty else { return }
        do {
            let ok = try await NeteaseAPI.shared.login(phone: phone, password: password)
            await MainActor.run { loginMsg = ok ? "登录成功" : "登录失败" }
        } catch {
            await MainActor.run { loginMsg = error.localizedDescription }
        }
    }
}
