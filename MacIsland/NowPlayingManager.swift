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
    /// Music.app's `sound volume` is on a 0–100 scale. Mirrored here so
    /// the SwiftUI volume slider can two-way bind without each tick
    /// triggering a TCC-gated AppleScript round-trip.
    @Published var volume: Double = 50

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
    /// Music.app's DNC payload has no artwork — we cache the AppleScript
    /// result here per track and surface it via `republish()`.
    private var musicAppArtwork: NSImage?
    /// Whichever source we believe is actively playing right now. When
    /// both apps are paused/stopped, `nil` and the view shows empty.
    private var activeSource: Source?

    private var lastTrackFingerprint: String?

    /// Local extrapolation of `elapsed` between notifications so the
    /// progress bar moves smoothly. Spotify ships current position in
    /// every notification; Music.app's DNC payload doesn't include
    /// position at all, so for Music.app we get accurate position only
    /// from `MusicAppBridge.currentSnapshot()` (poll) or
    /// `currentPosition()` (per-notification fetch).
    private var tickTimer: Timer?

    /// Safety net for missed Music.app DNC notifications (e.g. when the
    /// user minimises the Music.app window — Music.app skips emitting
    /// some events in that state, which previously left our chip
    /// stuck on the wrong isPlaying value). Polls
    /// `MusicAppBridge.currentSnapshot()` every few seconds and
    /// reconciles. Spotify is consistently reliable via DNC so it
    /// doesn't need a poll.
    private var musicAppPollTimer: Timer?

    /// In-flight artwork fetch task we cancel when track changes.
    private var artworkFetchTask: URLSessionDataTask?

    init() {
        let center = DistributedNotificationCenter.default()

        // Per-app fallback observers (Music.app + Spotify) — kept
        // active alongside MediaRemote so we still have a working
        // path on macOS versions where MR is locked down.
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
        musicAppPollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollMusicApp()
        }
    }

    deinit {
        tickTimer?.invalidate()
        musicAppPollTimer?.invalidate()
        artworkFetchTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - DNC handlers

    @objc private func handleMusicAppNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        // Diagnostic: dump the keys we received so we can debug edge
        // cases like "minimize Music.app hides the chip" without
        // having to attach a debugger.
        NSLog("[NowPlayingManager] Music.app notification keys: %@",
              Array(info.keys).sorted().description)
        guard let state = parseMusicApp(info) else { return }

        // Apply the partial state (title/artist/album/duration/isPlaying)
        // immediately so the UI updates without waiting on AppleScript.
        musicAppState = state
        recomputeActiveSource()
        republish()

        // Then enrich with AppleScript-fetched fields async (artwork,
        // position, volume).
        refreshMusicAppFromBridge()
    }

    @objc private func handleSpotifyNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        NSLog("[NowPlayingManager] Spotify notification keys: %@",
              Array(info.keys).sorted().description)
        guard let state = parseSpotify(info) else { return }
        spotifyState = state
        recomputeActiveSource()
        republish()
    }


    // MARK: - Parsers

    /// Parse Music.app's `com.apple.iTunes.playerInfo` payload, defensively.
    /// Returns nil when the payload doesn't look like a real playback
    /// notification (no Name and no Player State) — this is what fires
    /// on minimize/hide and would otherwise drop us into "isPlaying =
    /// false" and hide the chip.
    private func parseMusicApp(_ info: [String: Any]) -> SourceState? {
        let nameField = info["Name"] as? String
        let stateField = info["Player State"] as? String
        guard nameField != nil || stateField != nil else {
            NSLog("[NowPlayingManager] Music.app notification has no Name/Player State; ignoring (likely a window state ping).")
            return nil
        }

        let prev = musicAppState
        let totalMs = info["Total Time"] as? Double ?? 0
        let resolvedDuration: TimeInterval = totalMs > 0
            ? totalMs / 1000.0
            : prev?.duration ?? 0

        let resolvedIsPlaying: Bool
        switch stateField {
        case "Playing": resolvedIsPlaying = true
        case "Paused", "Stopped": resolvedIsPlaying = false
        default: resolvedIsPlaying = prev?.isPlaying ?? false
        }

        // Music.app's DNC payload has no `Playback Position` field, so on
        // pause/resume we'd otherwise overwrite the previous elapsed time
        // with 0 — visibly resetting the progress bar until the
        // AppleScript bridge poll repaired it. Preserve the previous
        // extrapolated elapsed so the bar holds its position. The
        // bridge enrichment that follows the handler will overwrite
        // with ground truth when AppleScript returns.
        let preservedElapsed: TimeInterval
        if let prev {
            let drift = prev.isPlaying
                ? Date().timeIntervalSince(prev.notificationTime)
                : 0
            preservedElapsed = max(prev.elapsedAtNotification + drift, 0)
        } else {
            preservedElapsed = 0
        }

        return SourceState(
            title: nameField ?? prev?.title,
            artist: (info["Artist"] as? String) ?? prev?.artist,
            album: (info["Album"] as? String) ?? prev?.album,
            duration: resolvedDuration,
            elapsedAtNotification: preservedElapsed,
            notificationTime: Date(),
            artworkURL: nil,
            isPlaying: resolvedIsPlaying
        )
    }

    private func parseSpotify(_ info: [String: Any]) -> SourceState? {
        let nameField = info["Name"] as? String
        let stateField = info["Player State"] as? String
        guard nameField != nil || stateField != nil else { return nil }

        let prev = spotifyState
        let durationMs = info["Duration"] as? Double ?? 0
        let positionSec = info["Playback Position"] as? Double
        let urlString = info["Artwork URL"] as? String

        let resolvedIsPlaying: Bool
        switch stateField {
        case "Playing": resolvedIsPlaying = true
        case "Paused", "Stopped": resolvedIsPlaying = false
        default: resolvedIsPlaying = prev?.isPlaying ?? false
        }

        return SourceState(
            title: nameField ?? prev?.title,
            artist: (info["Artist"] as? String) ?? prev?.artist,
            album: (info["Album"] as? String) ?? prev?.album,
            duration: durationMs > 0 ? durationMs / 1000.0 : prev?.duration ?? 0,
            elapsedAtNotification: positionSec ?? prev?.elapsedAtNotification ?? 0,
            notificationTime: Date(),
            artworkURL: urlString.flatMap(URL.init(string:)) ?? prev?.artworkURL,
            isPlaying: resolvedIsPlaying
        )
    }

    // MARK: - Fan-out

    private func currentState() -> SourceState? {
        switch activeSource {
        case .musicApp: return musicAppState
        case .spotify: return spotifyState
        case .none:
            // None playing — show whichever has a track loaded so the
            // user can see "X is paused" without the chip appearing
            // empty.
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

        // Diagnostic: log every nil ↔ non-nil title transition. If the
        // expanded panel ever flickers between music view and home view
        // again, this is what surfaces the cause.
        let hadTitle = (title?.isEmpty == false)
        let hasTitleNow = (newTitle?.isEmpty == false)
        if hadTitle != hasTitleNow {
            NSLog("[NowPlayingManager] title presence changed: had=%@ now=%@ (title=%@)",
                  hadTitle ? "true" : "false",
                  hasTitleNow ? "true" : "false",
                  newTitle ?? "<nil>")
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
            // Drop the Music.app artwork cache when the track changes
            // so we don't briefly render the previous song's art
            // before the new AppleScript fetch returns.
            if activeSource == .musicApp { musicAppArtwork = nil }
            lastTrackFingerprint = fingerprint
        }

        // Pull whichever artwork source matches the active player.
        switch activeSource {
        case .spotify:
            if let url = state?.artworkURL, artwork == nil {
                fetchArtwork(from: url)
            }
        case .musicApp:
            if let cached = musicAppArtwork {
                artwork = cached
            }
        case .none:
            break
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

    // MARK: - Playback commands

    /// Verbs are identical for Music.app and Spotify — both apps
    /// expose `playpause`, `next track`, and `previous track` in their
    /// AppleScript dictionaries — so we route by active source rather
    /// than per-app dispatch.
    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    func send(_ command: Command) {
        let appName: String
        switch activeSource {
        case .musicApp: appName = "Music"
        case .spotify: appName = "Spotify"
        case .none:
            // Fall back to whichever source has a track loaded so the
            // user can resume playback after pausing both apps.
            if musicAppState?.title != nil {
                appName = "Music"
            } else if spotifyState?.title != nil {
                appName = "Spotify"
            } else {
                return
            }
        }
        let source = "tell application \"\(appName)\" to \(command.rawValue)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("[NowPlayingManager] %@ %@ failed: %@", appName, command.rawValue, error)
            }
        }
    }

    // MARK: - Music.app safety-net poll + bridge enrichment

    /// Timestamp of the most recent user-driven volume change, used to
    /// suppress feedback loops where a slider drag races a 3s poll
    /// snapshot of the old volume value.
    private var lastSetVolumeTime: Date?

    private func pollMusicApp() {
        refreshMusicAppFromBridge()
    }

    /// Pulls the canonical state from Music.app via AppleScript
    /// (snapshot + artwork) and reconciles. Used both immediately
    /// after a DNC notification fires (to fill in fields the
    /// notification doesn't include) and on the safety-net poll
    /// timer (to recover from missed/stale DNC events — most
    /// notably: minimising the Music.app window).
    private func refreshMusicAppFromBridge() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let snapshot = MusicAppBridge.currentSnapshot()
            let artwork = MusicAppBridge.currentArtwork()
            DispatchQueue.main.async {
                self?.applyMusicAppBridge(snapshot: snapshot, artwork: artwork)
            }
        }
    }

    /// The bridge is **purely an enrichment path**. It updates volume,
    /// position, duration, artwork, and isPlaying when it has fresh
    /// data — but it never drops `musicAppState`. Lifecycle is DNC's
    /// exclusive job (each `playerInfo` notification is a "this track
    /// is now what's loaded" event from Music.app's authoritative
    /// state). Without this rule, the bridge's transient nil snapshots
    /// (Music.app briefly reports "stopped" between tracks, during
    /// burst notifications, on window minimise, on focus changes)
    /// would clear cached title/artist and the expanded panel would
    /// flicker between music and home views while a track was actually
    /// still loaded.
    private func applyMusicAppBridge(snapshot: MusicAppBridge.Snapshot?, artwork: NSImage?) {
        // Volume: skip if the user just dragged the slider — otherwise
        // the next poll would yank the slider back to the previous
        // server-side value before the AppleScript "set" had time to
        // land.
        if let v = snapshot?.volume {
            let recentlyTouched = lastSetVolumeTime.map { Date().timeIntervalSince($0) < 1.0 } ?? false
            if !recentlyTouched, abs(v - volume) > 0.5 {
                volume = v
            }
        }

        guard let snapshot else {
            // Music.app isn't running or AppleScript was denied — DNC
            // is what tells us when state genuinely changes. Leave
            // everything in place.
            return
        }

        guard let title = snapshot.title, !title.isEmpty else {
            // Bridge reports no track right now — could be a transient
            // gap. Don't touch state. Update artwork only if the bridge
            // happened to grab one.
            if let artwork {
                musicAppArtwork = artwork
            }
            return
        }

        var state = musicAppState ?? SourceState()
        state.title = title
        state.artist = snapshot.artist
        state.album = snapshot.album
        if snapshot.duration > 0 {
            state.duration = snapshot.duration
        }
        state.elapsedAtNotification = snapshot.position
        state.notificationTime = Date()
        state.isPlaying = snapshot.isPlaying
        musicAppState = state
        if artwork != nil {
            musicAppArtwork = artwork
        }

        recomputeActiveSource()
        republish()
    }

    /// Picks the best activeSource based on current per-source state.
    /// Looks at all sources in aggregate and applies the priority
    /// (MediaRemote > Music.app > Spotify) so a lower-priority DNC
    /// notification can't downgrade a higher-priority active source.
    private func recomputeActiveSource() {
        let musicPlaying = musicAppState?.isPlaying ?? false
        let spotifyPlaying = spotifyState?.isPlaying ?? false

        if musicPlaying {
            activeSource = .musicApp
        } else if spotifyPlaying {
            activeSource = .spotify
        } else {
            // None playing. Hold the previous source so the chip can
            // dissolve cleanly via the 0.5s grace in DynamicIslandView,
            // unless that source has nothing loaded at all.
            switch activeSource {
            case .musicApp where musicAppState?.title == nil:
                activeSource = nil
            case .spotify where spotifyState?.title == nil:
                activeSource = nil
            default:
                break
            }
        }
    }

    // MARK: - Volume

    /// Drives the macOS **system output volume** — the same thing
    /// the keyboard volume keys move. We previously routed this to
    /// `tell application "Music" to set sound volume`, which only
    /// adjusts Music.app's *internal* slider stacked on top of the
    /// system output: cranking it to 100 inside the app while system
    /// output sat at 65% capped perceived volume at 65%. Driving
    /// system output matches user expectation ("the volume keys
    /// move this slider, this slider moves the volume keys").
    func setVolume(_ value: Double) {
        let clamped = max(0, min(100, value))
        volume = clamped
        lastSetVolumeTime = Date()
        let source = "set volume output volume \(Int(clamped.rounded()))"
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }
}
