//
//  NowPlayingManager.swift
//  MacIsland
//
//  Thin registry over a set of NowPlayingSource implementations.
//
//  Each source observes one app or system surface (Music.app DNC,
//  Spotify DNC, the AX existence signal, …) and publishes its own
//  snapshot. The manager subscribes to every registered source, and
//  on each event picks the highest-priority one to surface via the
//  @Published interface this class has always exposed — title,
//  artist, album, artwork, isPlaying, duration, elapsed, volume —
//  so views are agnostic to which source produced the data.
//
//  Selection rule (see `reconcile()`):
//    1. Sources with isPlaying == true beat sources with
//       isPlaying == false. Music.app paused while a YouTube PWA
//       plays should yield to whatever's actually playing, even
//       though Music.app has richer metadata.
//    2. Among sources at equal play-state, higher snapshot.fidelity
//       wins. Full data from Music.app beats existence-only data
//       from AX.
//    3. Tie-break: the source registered first wins (stable across
//       reconciles).
//
//  Native-macOS now-playing constraints are documented in the README
//  and recorded in the `experiment/ax-now-playing` branch's commit
//  message. This class doesn't need to know the gap exists — sources
//  do.
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

    /// Fidelity of the active source. Views check this to adapt:
    /// when the active source is `.existence` (the system Now
    /// Playing menu-bar widget says something is playing but we
    /// can't read what), the chip renders a generic "Now Playing"
    /// placeholder and the expanded view hides transport controls.
    @Published private(set) var fidelity: NowPlayingSnapshot.Fidelity?

    /// Capabilities of the currently active source. Views grey out
    /// buttons that wouldn't do anything (the AX existence source
    /// declares `.none` since it has no transport channel).
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

    /// True when there's anything worth showing in the chip — either
    /// real track text from a full-fidelity source, or the
    /// system-wide "something is playing" signal from the AX
    /// existence source. Views drive showMusicAsDefault from this.
    var hasTrack: Bool {
        if let title, !title.isEmpty { return true }
        return fidelity == .existence && isPlaying
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
        // Order matters: the manager's tie-break on equal fidelity +
        // play-state goes to whichever source registered first. AX
        // existence sits at the bottom because its fidelity is
        // already the lowest, but registering it last makes intent
        // explicit.
        register(MusicAppSource())
        register(SpotifySource())
        register(AXExistenceSource())

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
    /// added earlier win when fidelity and play-state are equal.
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

        var best: (NowPlayingSource, NowPlayingSnapshot)?
        for candidate in candidates {
            guard let current = best else { best = candidate; continue }
            if isCandidate(candidate, betterThan: current) {
                best = candidate
            }
        }

        activeSource = best?.0
        activeControls = best?.0.controlsCapability ?? .none
        publish(best?.1)
    }

    private func isCandidate(
        _ a: (NowPlayingSource, NowPlayingSnapshot),
        betterThan b: (NowPlayingSource, NowPlayingSnapshot)
    ) -> Bool {
        // 1. Playing wins over paused.
        if a.1.isPlaying != b.1.isPlaying {
            return a.1.isPlaying
        }
        // 2. Higher fidelity wins.
        if a.1.fidelity != b.1.fidelity {
            return a.1.fidelity > b.1.fidelity
        }
        // 3. Tie — keep the existing best (registration order).
        return false
    }

    private func publish(_ snapshot: NowPlayingSnapshot?) {
        title = snapshot?.title
        artist = snapshot?.artist
        album = snapshot?.album
        artwork = snapshot?.artwork
        isPlaying = snapshot?.isPlaying ?? false
        duration = snapshot?.duration ?? 0
        elapsed = snapshot?.elapsed ?? 0
        fidelity = snapshot?.fidelity
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
