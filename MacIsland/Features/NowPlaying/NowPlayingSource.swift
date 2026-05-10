//
//  NowPlayingSource.swift
//  MacIsland
//
//  Protocol that every now-playing data origin conforms to. Music.app
//  and Spotify each publish via DNC + AppleScript with full track
//  metadata; future AppleScript-bridgeable apps (Apple Podcasts, VLC,
//  IINA, …) plug in via the same shape so `NowPlayingManager` stays a
//  thin registry that doesn't grow a switch statement per app.
//
//  Browser / PWA audio is intentionally out of scope: the only signal
//  macOS exposes there is "the system Now Playing widget exists",
//  which fires for paused tracks too and produces a worse UX than
//  showing nothing. See git history for the AX-existence experiment.
//

import AppKit
import Combine
import Foundation

/// One concrete origin of now-playing state.
///
/// Implementations are responsible for their own observation strategy
/// (DNC subscription, AppleScript polling, AX walking, etc.) and for
/// publishing a `changes` event whenever their internal state moves.
/// They expose a snapshot on demand; the manager pulls + reconciles.
protocol NowPlayingSource: AnyObject {
    /// Stable identifier for diagnostics and active-source bookkeeping.
    /// Conventional form: dot-separated lower-case
    /// ("music.app", "spotify").
    var identifier: String { get }

    /// Current snapshot from this source, or nil if it has nothing
    /// loaded right now. Sources should NOT return a snapshot with
    /// stale data after the underlying app has clearly stopped — let
    /// the manager fall through to the next source.
    var snapshot: NowPlayingSnapshot? { get }

    /// Publisher fired whenever `snapshot` may have changed. The
    /// manager subscribes once and reconciles on every event.
    /// Implementations should debounce or coalesce internally — the
    /// manager treats every event as "re-evaluate everything".
    var changes: AnyPublisher<Void, Never> { get }

    /// Which transport commands this source can dispatch. Used by the
    /// view layer to grey out controls that won't do anything.
    var controlsCapability: NowPlayingControls { get }

    /// Dispatch a transport command. No-op if the source doesn't
    /// support the command (callers should consult `controlsCapability`
    /// first, but defensive sources should also tolerate unsupported
    /// commands silently).
    func send(_ command: NowPlayingCommand)
}

/// Best-known snapshot of "what's playing" from one source.
struct NowPlayingSnapshot {
    var title: String?
    var artist: String?
    var album: String?
    var artwork: NSImage?

    /// Track duration in seconds. 0 when unknown.
    var duration: TimeInterval = 0

    /// Position when `elapsedAtSampleTime` was sampled. The manager
    /// extrapolates a smooth elapsed-time forward from this anchor
    /// using the local clock — sources don't have to keep updating it.
    var elapsed: TimeInterval = 0

    /// When `elapsed` was last sampled from the underlying source.
    /// Defaults to "now" so freshly-built snapshots don't have a
    /// suspicious zero value.
    var elapsedAtSampleTime: Date = Date()

    /// True when the user is currently hearing audio from this source.
    /// Pause / stop / "loaded but not started" should be `false`.
    var isPlaying: Bool = false

    /// True when the snapshot has enough text to render in the chip.
    var hasTrack: Bool {
        guard let title, !title.isEmpty else { return false }
        return true
    }
}

/// Transport commands a source might accept.
enum NowPlayingCommand {
    case playPause
    case next
    case previous
}

/// Bitmask of supported commands. Per-source declaration so the view
/// can grey out unsupported buttons.
struct NowPlayingControls: OptionSet {
    let rawValue: Int

    static let playPause = NowPlayingControls(rawValue: 1 << 0)
    static let next      = NowPlayingControls(rawValue: 1 << 1)
    static let previous  = NowPlayingControls(rawValue: 1 << 2)

    static let none: NowPlayingControls = []
    static let all: NowPlayingControls = [.playPause, .next, .previous]
}
