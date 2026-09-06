import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

enum PlayMode: String, CaseIterable {
    case order
    case repeatOne
    case shuffle
    var systemImage: String {
        switch self {
        case .order: return "repeat"
        case .repeatOne: return "repeat.1"
        case .shuffle: return "shuffle"
        }
    }
}

/// Global playback controller backed by AVPlayer. Handles the queue, play
/// modes, playback speed, lyrics, lock-screen / Control Center metadata and
/// remote commands (Mpris-like on iOS via MPRemoteCommandCenter).
@MainActor
final class PlayerManager: ObservableObject {
    static let shared = PlayerManager()

    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserver: NSObjectProtocol?

    @Published var queue: [Track] = []
    @Published var currentIndex: Int = 0
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var playMode: PlayMode = .order
    @Published var playbackRate: Double = 1.0
    @Published var currentTrack: Track?
    @Published var isResolvingURL: Bool = false
    @Published var lyricLines: [LyricLine] = []
    @Published var lyricLoadFailed: Bool = false

    private var resolveTask: Task<Void, Never>?

    private init() {
        playbackRate = AppSettings.shared.playbackRate
        setupAudioSession()
        setupRemoteCommands()
        setupEndObserver()
    }

    deinit {
        if let token = timeObserverToken { player?.removeTimeObserver(token) }
        if let obs = endObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Audio session

    private func setupAudioSession() {
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default,
                              options: [.allowAirPlay])
            try s.setActive(true)
        } catch {
            #if DEBUG
            print("AVAudioSession error: \(error)")
            #endif
        }
    }

    // MARK: - Queue control

    func playQueue(_ tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = min(max(index, 0), tracks.count - 1)
        loadCurrentTrack()
    }

    func playTrack(_ track: Track) {
        // Play a single track as a one-item queue.
        playQueue([track], startAt: 0)
    }

    private func loadCurrentTrack() {
        guard queue.indices.contains(currentIndex) else { return }
        let track = queue[currentIndex]
        currentTrack = track
        currentTime = 0
        duration = track.duration
        lyricLines = []
        lyricLoadFailed = false

        // Offline: play a previously downloaded file directly.
        if let local = LibraryStore.shared.localPath(for: track.id) {
            Task { [weak self] in
                do {
                    let (lrc, _) = try await NeteaseAPI.shared.lyric(id: track.id)
                    await MainActor.run {
                        self?.lyricLines = LyricsParser.parse(lrc)
                        self?.lyricLoadFailed = lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                } catch {
                    await MainActor.run { self?.lyricLines = []; self?.lyricLoadFailed = true }
                }
            }
            startPlayback(url: URL(fileURLWithPath: local))
            updateNowPlaying()
            return
        }

        // Resolve lyrics.
        Task { [weak self] in
            do {
                let (lrc, _) = try await NeteaseAPI.shared.lyric(id: track.id)
                await MainActor.run {
                    self?.lyricLines = LyricsParser.parse(lrc)
                    self?.lyricLoadFailed = lrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            } catch {
                await MainActor.run { self?.lyricLines = []; self?.lyricLoadFailed = true }
            }
        }

        // Resolve playable URL.
        resolveTask?.cancel()
        isResolvingURL = true
        resolveTask = Task { [weak self] in
            do {
                let urlStr = try await NeteaseAPI.shared.songURL(
                    id: track.id, level: AppSettings.shared.audioQuality.rawValue)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.isResolvingURL = false }
                guard let self, let urlStr, let url = URL(string: urlStr) else {
                    await MainActor.run { self?.skipUnavailable() }
                    return
                }
                await MainActor.run { self.startPlayback(url: url) }
            } catch {
                await MainActor.run {
                    self?.isResolvingURL = false
                    self?.skipUnavailable()
                }
            }
        }
        updateNowPlaying()
    }

    private func skipUnavailable() {
        // Auto-advance if a track can't be resolved.
        if queue.count > 1 {
            next()
        } else {
            pause()
        }
    }

    private func startPlayback(url: URL) {
        let item = AVPlayerItem(url: url)
        if player == nil {
            player = AVPlayer(playerItem: item)
            attachTimeObserver()
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.rate = Float(playbackRate)
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func play() {
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() } else { play() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        if playMode == .shuffle, queue.count > 1 {
            var i = currentIndex
            while i == currentIndex { i = Int.random(in: 0..<queue.count) }
            currentIndex = i
        } else if currentIndex < queue.count - 1 {
            currentIndex += 1
        } else {
            currentIndex = 0
        }
        loadCurrentTrack()
    }

    func previous() {
        if let p = player, p.currentTime().seconds > 3 {
            p.seek(to: .zero)
            currentTime = 0
            return
        }
        guard !queue.isEmpty else { return }
        currentIndex = currentIndex > 0 ? currentIndex - 1 : queue.count - 1
        loadCurrentTrack()
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        currentTime = time
        updateNowPlayingProgress()
    }

    func cyclePlayMode() {
        let all = PlayMode.allCases
        if let idx = all.firstIndex(of: playMode) {
            playMode = all[(idx + 1) % all.count]
        }
    }

    func setRate(_ rate: Double) {
        playbackRate = rate
        player?.rate = Float(rate)
        AppSettings.shared.playbackRate = rate
        updateNowPlaying()
    }

    var currentLyricIndex: Int {
        let t = currentTime
        guard !lyricLines.isEmpty else { return -1 }
        var idx = 0
        for (i, line) in lyricLines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }

    // MARK: - Time observer

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.4, preferredTimescale: 600)
        timeObserverToken = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                if let dur = self.player?.currentItem?.duration.seconds, dur.isFinite {
                    self.duration = dur
                }
                self.updateNowPlayingProgress()
            }
        }
    }

    private func setupEndObserver() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.playMode == .repeatOne {
                    self.player?.seek(to: .zero)
                    self.player?.play()
                } else {
                    self.next()
                }
            }
        }
    }

    // MARK: - Now Playing / Remote commands

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.displayArtist,
            MPMediaItemPropertyAlbumTitle: track.displayAlbum,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: playbackRate,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        if let cover = track.coverURL, let u = URL(string: cover) {
            Task {
                if let data = try? Data(contentsOf: u),
                   let img = UIImage(data: data) {
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    updated[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }
        }
    }

    private func updateNowPlayingProgress() {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        if duration.isFinite { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in self?.play(); return .success }
        center.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        center.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        center.changePlaybackRateCommand.addTarget { [weak self] event in
            if let rate = (event as? MPChangePlaybackRateCommandEvent)?.playbackRate {
                self?.setRate(Double(rate))
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let pos = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime {
                self?.seek(to: pos)
            }
            return .success
        }
    }
}
