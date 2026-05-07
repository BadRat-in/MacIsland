//
//  NowPlayingManager.swift
//  MacIsland
//
//  Now-playing detection on native macOS in 2026 is constrained: every
//  public API for *system-wide* now-playing info is `@available(macos,
//  unavailable)` (MPMusicPlayerController, MusicKit's SystemMusicPlayer)
//  and the private MediaRemote.framework now returns "Operation not
//  permitted" from `mediaremoted` regardless of sandbox/codesigning,
//  starting roughly with macOS 15.
//
//  The pragmatic substitute used here: DistributedNotificationCenter
//  observers for the two native macOS music apps that broadcast
//  playback state — Music.app and Spotify. This covers the common
//  case but **does not detect browser audio (YouTube, web players),
//  podcast apps, or anything that doesn't post to DNC.** That gap is
//  outside our control; if Apple ships a public surface or relaxes
//  MediaRemote, we'll route through it.
//
//  Public interface (`@Published` properties + `.nowPlayingTrackChanged`)
//  matches the previous MediaRemote-based implementation, so views and
//  controllers don't change.
//

import AppKit
import Combine
import Foundation

final class NowPlayingManager: ObservableObject {
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var album: String?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0

    /// Kept on the public interface so the view layer doesn't have to
    /// change. With the DNC-based implementation this is always true —
    /// listeners attach successfully regardless of which apps are running.
    let isAvailable: Bool = true

    var hasTrack: Bool {
        guard let title, !title.isEmpty else { return false }
        return true
    }

    private enum Source {
        case musicApp
        case spotify
    }

    private struct SourceState {
        var title: String?
        var artist: String?
        var album: String?
        var duration: TimeInterval = 0
        var elapsedAtNotification: TimeInterval = 0
        var notificationTime: Date = Date()
        var artworkURL: URL?
        var isPlaying: Bool = false
    }

    private var musicAppState: SourceState?
    private var spotifyState: SourceState?
    /// Whichever source we believe is actively playing right now. When
    /// both apps are paused/stopped, `nil` and the view shows empty.
    private var activeSource: Source?

    private var lastTrackFingerprint: String?

    /// Local extrapolation of `elapsed` between notifications so the
    /// progress bar moves smoothly. Spotify ships current position in
    /// every notification; Music.app doesn't, so for Music.app this
    /// extrapolates from 0 (acceptable degradation; accurate position
    /// would require a ScriptingBridge AppleScript and an Automation
    /// TCC prompt, deferred to the controls PR).
    private var tickTimer: Timer?

    /// In-flight artwork fetch task we cancel when track changes.
    private var artworkFetchTask: URLSessionDataTask?

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            self,
            selector: #selector(handleMusicAppNotification(_:)),
            name: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        NSLog("[NowPlayingManager] DNC observers attached for Music.app + Spotify")

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickElapsed()
        }
    }

    deinit {
        tickTimer?.invalidate()
        artworkFetchTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - DNC handlers

    @objc private func handleMusicAppNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let state = parseMusicApp(info)
        musicAppState = state
        updateActiveSource(.musicApp, isPlaying: state.isPlaying)
        republish()
    }

    @objc private func handleSpotifyNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        let state = parseSpotify(info)
        spotifyState = state
        updateActiveSource(.spotify, isPlaying: state.isPlaying)
        republish()
    }

    private func updateActiveSource(_ source: Source, isPlaying: Bool) {
        if isPlaying {
            activeSource = source
        } else if activeSource == source {
            // Source we were tracking just paused/stopped; defer to the
            // other source if it has anything.
            switch source {
            case .musicApp:
                activeSource = (spotifyState?.isPlaying == true) ? .spotify : nil
            case .spotify:
                activeSource = (musicAppState?.isPlaying == true) ? .musicApp : nil
            }
        }
    }

    // MARK: - Parsers

    private func parseMusicApp(_ info: [String: Any]) -> SourceState {
        let totalMs = info["Total Time"] as? Double ?? 0
        return SourceState(
            title: info["Name"] as? String,
            artist: info["Artist"] as? String,
            album: info["Album"] as? String,
            duration: totalMs / 1000.0,
            elapsedAtNotification: 0, // not provided by Music.app DNC payload
            notificationTime: Date(),
            artworkURL: nil,
            isPlaying: (info["Player State"] as? String) == "Playing"
        )
    }

    private func parseSpotify(_ info: [String: Any]) -> SourceState {
        let durationMs = info["Duration"] as? Double ?? 0
        let positionSec = info["Playback Position"] as? Double ?? 0
        let urlString = info["Artwork URL"] as? String
        return SourceState(
            title: info["Name"] as? String,
            artist: info["Artist"] as? String,
            album: info["Album"] as? String,
            duration: durationMs / 1000.0,
            elapsedAtNotification: positionSec,
            notificationTime: Date(),
            artworkURL: urlString.flatMap(URL.init(string:)),
            isPlaying: (info["Player State"] as? String) == "Playing"
        )
    }

    // MARK: - Fan-out

    private func currentState() -> SourceState? {
        switch activeSource {
        case .musicApp: return musicAppState
        case .spotify: return spotifyState
        case .none:
            // Both inactive — show whichever has a track loaded so the
            // user can see "X is paused" without it appearing as empty.
            if let m = musicAppState, m.title != nil { return m }
            if let s = spotifyState, s.title != nil { return s }
            return nil
        }
    }

    private func republish() {
        let state = currentState()

        let newTitle = state?.title
        let newArtist = state?.artist
        let fingerprint = (newTitle ?? "") + "\u{1f}" + (newArtist ?? "")
        let trackChanged = fingerprint != lastTrackFingerprint

        if trackChanged && newTitle != nil {
            NSLog("[NowPlayingManager] now playing → %@ — %@",
                  newTitle ?? "<nil>",
                  newArtist ?? "<nil>")
        }

        title = newTitle
        artist = newArtist
        album = state?.album
        duration = state?.duration ?? 0
        elapsed = state?.elapsedAtNotification ?? 0
        isPlaying = state?.isPlaying ?? false

        if trackChanged {
            artwork = nil
            artworkFetchTask?.cancel()
            artworkFetchTask = nil
            if let url = state?.artworkURL {
                fetchArtwork(from: url)
            }
            lastTrackFingerprint = fingerprint
            if let title = newTitle, !title.isEmpty {
                NotificationCenter.default.post(name: .nowPlayingTrackChanged, object: nil)
            }
        }
    }

    private func tickElapsed() {
        guard isPlaying, let state = currentState() else { return }
        let drift = Date().timeIntervalSince(state.notificationTime)
        elapsed = min(state.elapsedAtNotification + drift, max(state.duration, 0))
    }

    private func fetchArtwork(from url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                self.artwork = image
            }
        }
        artworkFetchTask = task
        task.resume()
    }
}
