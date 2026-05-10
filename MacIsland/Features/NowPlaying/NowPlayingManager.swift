//
//  NowPlayingManager.swift
//  MacIsland
//
//  Thin registry over a set of NowPlayingSource implementations.
//
//  Each source observes one AppleScript-bridgeable app (Music.app,
//  Spotify, …) and publishes its own snapshot. The manager subscribes
//  to every registered source, and on each event picks one to surface
//  via the @Published interface — title, artist, album, artwork,
//  isPlaying, duration, elapsed, volume — so views stay agnostic to
//  which source produced the data.
//
//  Selection rule (see `reconcile()`):
//    1. A source reporting isPlaying == true wins over any paused
//       source. Music.app paused while Spotify plays should yield to
//       Spotify.
//    2. Tie-break: the source registered first wins (stable across
//       reconciles), so paused-Music keeps showing its track when
//       nothing else is active.
//
//  Browser / PWA audio is intentionally unsupported — macOS only
//  exposes a "system widget exists" bit there, which fires for
//  paused tracks too and makes the chip lie. See git history for
//  the AX-existence experiment.
//

import AppKit
import Combine
import Foundation

final class NowPlayingManager: ObservableObject {
    // Public shape preserved for the view layer.
    @Published private(set) var title: String?
    @Published private(set) var artist: String?
    @Published private(set) var album: String?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var elapsed: TimeInterval = 0

    /// Capabilities of the currently active source. Views grey out
    /// buttons that wouldn't do anything.
    @Published private(set) var activeControls: NowPlayingControls = .none

    /// Mirrors macOS system output volume on a 0–100 scale. The
    /// slider in the music view two-way-binds to this; `setVolume(_:)`
    /// writes through to the system. Polled every 3 s so external
    /// changes (volume keys, Sound preferences) keep the slider in
    /// sync.
    @Published var volume: Double = 50

    /// Kept on the public interface for view-layer compatibility.
    /// Always true with the source-registry implementation — even if
    /// every source returns nil, the registry itself is alive and
    /// listening.
    let isAvailable: Bool = true

    /// True when there's anything worth showing in the chip. Views
    /// drive showMusicAsDefault from this.
    var hasTrack: Bool {
        if let title, !title.isEmpty { return true }
        return false
    }

    /// Public command type kept so existing
    /// `nowPlayingManager.send(.playPause)` call sites keep
    /// compiling. Maps internally to `NowPlayingCommand`.
    enum Command {
        case playPause
        case next
        case previous
    }

    // MARK: - Source registry

    private(set) var sources: [NowPlayingSource] = []
    private(set) var activeSource: NowPlayingSource?

    private var cancellables: Set<AnyCancellable> = []

    /// Drives smooth elapsed-time extrapolation between source
    /// updates so the progress bar advances even when the underlying
    /// source only emits an event every few seconds.
    private var tickTimer: Timer?

    /// Polls system output volume so external changes keep our
    /// slider honest.
    private var volumePollTimer: Timer?

    /// Suppresses the volume poll for ~1 s after the user drags the
    /// slider — without this the poll could yank the slider back to
    /// a stale server-side value before our `set volume output volume`
    /// AppleScript had time to take effect.
    private var lastSetVolumeTime: Date?

    init() {
        // Registration order is the tie-breaker when no source is
        // playing — Music.app first means a paused Music track keeps
        // surfacing while Spotify is idle.
        register(MusicAppSource())
        register(SpotifySource())

        if let v = SystemVolume.current() {
            volume = v
        }

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tickElapsed()
        }
        volumePollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.pollSystemVolume()
        }

        NSLog("[NowPlayingManager] registered %d sources: %@",
              sources.count,
              sources.map(\.identifier).joined(separator: ", "))
    }

    deinit {
        tickTimer?.invalidate()
        volumePollTimer?.invalidate()
    }

    /// Registers a source. Order matters as a tie-breaker — sources
    /// added earlier win when no source is currently playing.
    private func register(_ source: NowPlayingSource) {
        sources.append(source)
        source.changes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.reconcile()
            }
            .store(in: &cancellables)
    }

    private func reconcile() {
        let candidates: [(NowPlayingSource, NowPlayingSnapshot)] = sources.compactMap { source in
            source.snapshot.map { (source, $0) }
        }

        // Pick the first source that's actually playing. If none are,
        // fall back to whichever paused source registered first so the
        // chip can fade out gracefully (DynamicIslandView's 0.5s grace
        // gives the user a moment to resume before the chip leaves).
        let best = candidates.first(where: { $0.1.isPlaying }) ?? candidates.first

        activeSource = best?.0
        activeControls = best?.0.controlsCapability ?? .none
        publish(best?.1)
    }

    private func publish(_ snapshot: NowPlayingSnapshot?) {
        title = snapshot?.title
        artist = snapshot?.artist
        album = snapshot?.album
        artwork = snapshot?.artwork
        isPlaying = snapshot?.isPlaying ?? false
        duration = snapshot?.duration ?? 0
        elapsed = snapshot?.elapsed ?? 0
    }

    private func tickElapsed() {
        guard isPlaying,
              let active = activeSource,
              let s = active.snapshot,
              s.duration > 0
        else { return }
        let drift = Date().timeIntervalSince(s.elapsedAtSampleTime)
        elapsed = min(s.elapsed + drift, s.duration)
    }

    // MARK: - Public commands

    func send(_ command: Command) {
        let mapped: NowPlayingCommand
        switch command {
        case .playPause: mapped = .playPause
        case .next:      mapped = .next
        case .previous:  mapped = .previous
        }

        if let active = activeSource {
            active.send(mapped)
            return
        }
        // Nothing actively playing — fall back to whichever source
        // has a track loaded so the user can resume after pausing.
        for source in sources where source.snapshot?.title != nil {
            source.send(mapped)
            return
        }
    }

    func setVolume(_ value: Double) {
        let clamped = max(0, min(100, value))
        volume = clamped
        lastSetVolumeTime = Date()
        SystemVolume.set(clamped)
    }

    private func pollSystemVolume() {
        guard let v = SystemVolume.current() else { return }
        let recentlySet = lastSetVolumeTime.map { Date().timeIntervalSince($0) < 1.0 } ?? false
        guard !recentlySet, abs(v - volume) > 0.5 else { return }
        volume = v
    }
}
