# AlgerMusicPlayer for iOS

**Alger Music Player 的 iOS 移植版**（原生 SwiftUI 实现），支持 **iPhone 与 iPad**（通用 App，iOS 16.5+）。

原项目（[1970905901/AlgerMusicPlayer](https://github.com/1970905901/AlgerMusicPlayer)）是一个基于 Electron + Vue3 的第三方网易云音乐播放器。
由于 iOS 无法运行 Electron 本地 Node 服务，本移植版改为**原生 SwiftUI App**，直接调用原项目同款的
`netease-cloud-music-api-alger`（兼容 `netease-cloud-music-api`）HTTP 接口——所有网易云请求签名都在服务端完成，
客户端只发送普通 HTTP 请求即可。

## 功能

- 🔍 搜索：单曲 / 专辑 / 歌单 / 歌手
- 🎵 播放：后台播放、锁屏与控制中心（MPRemoteCommandCenter）、AirPlay、倍速、播放模式（顺序/单曲/随机）
- 📝 沉浸式歌词：逐行高亮、点击歌词跳转
- 📚 音乐库：我喜欢的音乐、本地歌单（增删）、云端歌单（登录后同步）
- 📥 离线下载：单曲可下载到本机，无网络也能播放（音乐库 → 已下载）
- 🎨 主题（跟随系统/浅色/深色）、音质选择（标准/较高/极高/无损）
- 📱 适配 iPhone 与 iPad：iPad 使用侧边栏分栏布局，支持多任务/横竖屏

## 构建与运行

> 需要一台 macOS 电脑（iOS App 只能在 macOS 的 Xcode 中编译；当前工程在 Windows 上生成源码，无法在此编译验证）。

### 1. 准备工具

```bash
brew install xcodegen      # 用 project.yml 生成 Xcode 工程
```

> 如果没有 `xcodegen`，也可以手动在 Xcode 里新建 iOS App 工程并把 `AlgerMusicPlayer/` 目录下的源码加进去。

### 2. 生成工程并运行

```bash
cd AlgerMusicPlayer-iOS
xcodegen generate
open AlgerMusicPlayer.xcodeproj
```

在 Xcode 中：

- 选择 `AlgerMusicPlayer` target → **Signing & Capabilities**，填入你的 Team（Bundle ID 改为你自己的，如 `com.yourname.music`）。
- 选择一台 iPhone/iPad 真机或模拟器，点击运行（⌘R）。
- 真机调试需在 **Signing** 中开启 **Background Modes → Audio**（工程已默认开启）。

### 3. 配置 API 服务（必须）

App 需要一个 `netease-cloud-music-api-alger` 实例作为后端。任选其一：

**方式 A：本地运行（电脑/服务器）**

```bash
# 基础接口
npx netease-cloud-music-api-alger
# 如需更高音质/解锁（可选）
npx @unblockneteasemusic/server
```

默认监听 `http://localhost:3000`。把它部署到手机能访问的地址（如同一局域网 `http://192.168.1.10:3000`），
然后在 App 内 **设置 → API 服务器地址** 填入该地址。

**方式 B：部署到公网 / 使用你已有的实例**

在设置中填入你的部署地址即可。

> 登录（手机号 + 密码）用于同步云端歌单；不登录也能正常搜索、播放、收藏。

## GitHub Actions 自动构建未签名 IPA

仓库已包含 `.github/workflows/build-unsigned-ipa.yml`：在 `ios` 分支推送或手动触发时，
在 macOS runner 上用 XcodeGen 生成工程并以**未签名**（无 Provisioning Profile）方式构建，
最终把 `AlgerMusicPlayer.app` 打包成 `AlgerMusicPlayer-unsigned.ipa` 作为 Artifact 上传。

> 未签名的 IPA 不能直接安装，需用 AltStore / Sideloadly 等工具在本地重新签名后侧载到 iPhone/iPad。

## 工程结构

```
AlgerMusicPlayer-iOS/
├── project.yml                 # XcodeGen 工程描述（iOS 16.5，通用设备，后台音频）
└── AlgerMusicPlayer/
    ├── AlgerMusicPlayerApp.swift
    ├── Models/                 # Track / Playlist / Album / Artist
    ├── Network/                # NeteaseAPI（接口客户端）+ APIModels
    ├── Player/                 # PlayerManager（AVPlayer + 锁屏/远程控制 + 歌词）
    ├── Persistence/            # AppSettings（UserDefaults）+ LibraryStore（本地歌单 JSON）
    ├── Utils/                  # LyricsParser / Extensions
    └── Views/                  # Home / Search / Library / NowPlaying / Lyrics / Settings / Detail / Components
```

## 说明与限制

- 本版为**原生重写**，并非直接复用原 Vue 代码（Electron/Node 本地服务无法在 iOS 运行）。
  设计语言与核心体验保持一致，离线下载、桌面歌词、EQ 等桌面专属能力未纳入。
- 播放地址解析依赖后端 API；个别歌曲若后端返回空地址会自动跳过。
- 仅用于学习交流，请支持正版。
