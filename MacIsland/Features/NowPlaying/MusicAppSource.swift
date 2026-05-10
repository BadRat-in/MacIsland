//
//  MusicAppSource.swift
//  MacIsland
//
//  NowPlayingSource for the macOS Music.app. Two observation paths
//  feed the same internal state:
//
//    1. DistributedNotificationCenter — the canonical lifecycle
//       channel (track changed, paused, stopped). Authoritative for
//       "is a track loaded?" questions; payload doesn't include
//       artwork or playback position.
//    2. MusicAppBridge AppleScript poll, every 3 s — fills in artwork
//       + accurate position + freshens isPlaying. Acts as a safety
//       net for events Music.app skips emitting (e.g. when its window
//       is minimised).
//
//  The bridge path is *enrichment-only*: it never drops snapshot
//  state on its own. Lifecycle (whether snapshot is nil or non-nil)
//  is exclusively DNC's responsibility, because Music.app briefly
//  reports "stopped" between tracks and during burst notifications,
//  and treating those transients as lifecycle events caused
//  observable flicker before this refactor.
//

import AppKit
import Combine
import Foundation

final class MusicAppSource: NowPlayingSource {
    let identifier = "music.app"
    let controlsCapability: NowPlayingControls = .all

    private(set) var snapshot: NowPlayingSnapshot?

    private let changesSubject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    private var pollTimer: Timer?

    init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNotification(_:)),
            name: NSNotification.Name("com.apple.iTunes.playerInfo"),
            object: nil
        )
        NSLog("[MusicAppSource] DNC observer attached")

        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshFromBridge()
        }
    }

    deinit {
        pollTimer?.invalidate()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - DNC

    @objc private func handleNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        NSLog("[MusicAppSource] notification keys: %@",
              Array(info.keys).sorted().description)
        guard let updated = parse(info) else { return }
        let trackChanged = updated.title != snapshot?.title
        snapshot = updated
        changesSubject.send()
        // After the immediate DNC update, fetch artwork + position via
        // AppleScript. Fresh artwork is the priority on track change;
        // otherwise we'd render the previous song's art briefly.
        if trackChanged, snapshot?.artwork != nil {
            // Drop the carried-over artwork from `parse` until the
            // bridge confirms the new track's art.
            var s = snapshot
            s?.artwork = nil
            snapshot = s
        }
        refreshFromBridge()
    }

    /// Defensive parser. Returns nil for payloads that look like
    /// non-playback events (no Name and no Player State); preserves
    /// the previous snapshot's title / artist / album / artwork
    /// across partial notifications (Music.app emits
    /// `["Player State"]`-only payloads on pause / resume).
    private func parse(_ info: [String: Any]) -> NowPlayingSnapshot? {
        let nameField = info["Name"] as? String
        let stateField = info["Player State"] as? String
        guard nameField != nil || stateField != nil else {
            NSLog("[MusicAppSource] notification has no Name/Player State; ignoring")
            return nil
        }

        let prev = snapshot
        let totalMs = info["Total Time"] as? Double ?? 0
        let resolvedDuration: TimeInterval = totalMs > 0
            ? totalMs / 1000
            : prev?.duration ?? 0

        let resolvedIsPlaying: Bool
        switch stateField {
        case "Playing": resolvedIsPlaying = true
        case "Paused", "Stopped": resolvedIsPlaying = false
        default: resolvedIsPlaying = prev?.isPlaying ?? false
        }

        // Music.app's DNC payload has no `Playback Position`; preserve
        // the extrapolated elapsed across notifications so the progress
        // bar doesn't reset to zero on every pause/resume tick. The
        // bridge-fetched value (position-aware AppleScript) overwrites
        // this with ground truth a few ms later.
        let preservedElapsed: TimeInterval
        if let prev {
            let drift = prev.isPlaying
                ? Date().timeIntervalSince(prev.elapsedAtSampleTime)
                : 0
            preservedElapsed = max(prev.elapsed + drift, 0)
        } else {
            preservedElapsed = 0
        }

        return NowPlayingSnapshot(
            title: nameField ?? prev?.title,
            artist: (info["Artist"] as? String) ?? prev?.artist,
            album: (info["Album"] as? String) ?? prev?.album,
            artwork: prev?.artwork,
            duration: resolvedDuration,
            elapsed: preservedElapsed,
            elapsedAtSampleTime: Date(),
            isPlaying: resolvedIsPlaying,
            fidelity: .full
        )
    }

    // MARK: - AppleScript bridge enrichment

    private func refreshFromBridge() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            let bridgeSnapshot = MusicAppBridge.currentSnapshot()
            let bridgeArtwork = MusicAppBridge.currentArtwork()
            DispatchQueue.main.async {
                self?.applyBridge(snapshot: bridgeSnapshot, artwork: bridgeArtwork)
            }
        }
    }

    /// Bridge enrichment only — never drops snapshot state. See file
    /// header for why lifecycle is exclusively DNC's job.
    private func applyBridge(snapshot bridgeSnapshot: MusicAppBridge.Snapshot?, artwork: NSImage?) {
        guard let bridgeSnapshot else {
            // Music.app not running or AppleScript denied. Leave
            // snapshot alone; DNC will straighten lifecycle out.
            return
        }

        guard let title = bridgeSnapshot.title, !title.isEmpty else {
            // Bridge reports no track right now — could be a transient
            // gap. Don't touch snapshot. Update artwork if we got one
            // anyway (cheap to surface).
            if let artwork, var current = snapshot {
                current.artwork = artwork
                snapshot = current
                changesSubject.send()
            }
            return
        }

        var current = snapshot ?? NowPlayingSnapshot(fidelity: .full)
        current.title = title
        current.artist = bridgeSnapshot.artist
        current.album = bridgeSnapshot.album
        if bridgeSnapshot.duration > 0 {
            current.duration = bridgeSnapshot.duration
        }
        current.elapsed = bridgeSnapshot.position
        current.elapsedAtSampleTime = Date()
        current.isPlaying = bridgeSnapshot.isPlaying
        current.fidelity = .full
        if artwork != nil {
            current.artwork = artwork
        }
        snapshot = current
        changesSubject.send()
    }

    // MARK: - Commands

    func send(_ command: NowPlayingCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next:      verb = "next track"
        case .previous:  verb = "previous track"
        }
        let source = "tell application \"Music\" to \(verb)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("[MusicAppSource] %@ failed: %@", verb, error)
            }
        }
    }
}
