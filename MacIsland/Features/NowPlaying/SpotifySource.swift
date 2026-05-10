//
//  SpotifySource.swift
//  MacIsland
//
//  NowPlayingSource for the Spotify desktop app. Spotify ships a
//  richer DNC payload than Music.app — title, artist, album, duration
//  in milliseconds, current playback position, and an artwork URL —
//  so this source doesn't need an AppleScript bridge to fill in
//  fields. It just observes DNC and fetches the artwork URL via
//  URLSession on track change.
//

import AppKit
import Combine
import Foundation

final class SpotifySource: NowPlayingSource {
    let identifier = "spotify"
    let controlsCapability: NowPlayingControls = .all

    private(set) var snapshot: NowPlayingSnapshot?

    private let changesSubject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    /// In-flight artwork fetch; cancelled when track changes so a
    /// slow response for the previous song doesn't overwrite the
    /// new song's artwork.
    private var artworkFetchTask: URLSessionDataTask?

    init() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleNotification(_:)),
            name: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
            object: nil
        )
        NSLog("[SpotifySource] DNC observer attached")
    }

    deinit {
        artworkFetchTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func handleNotification(_ note: Notification) {
        guard let info = note.userInfo as? [String: Any] else { return }
        NSLog("[SpotifySource] notification keys: %@",
              Array(info.keys).sorted().description)
        guard let parsed = parse(info) else { return }

        // Detect track change before swapping snapshot — drives the
        // artwork-fetch decision.
        let previousTitle = snapshot?.title
        snapshot = parsed
        changesSubject.send()

        let trackChanged = parsed.title != previousTitle
        if trackChanged {
            artworkFetchTask?.cancel()
            // Drop carried-over artwork until the new fetch completes.
            if var current = snapshot {
                current.artwork = nil
                snapshot = current
                changesSubject.send()
            }
            if let urlString = info["Artwork URL"] as? String,
               let url = URL(string: urlString) {
                fetchArtwork(from: url)
            }
        }
    }

    private func parse(_ info: [String: Any]) -> NowPlayingSnapshot? {
        let nameField = info["Name"] as? String
        let stateField = info["Player State"] as? String
        guard nameField != nil || stateField != nil else { return nil }

        let prev = snapshot
        let durationMs = info["Duration"] as? Double ?? 0
        let positionSec = info["Playback Position"] as? Double

        let resolvedIsPlaying: Bool
        switch stateField {
        case "Playing": resolvedIsPlaying = true
        case "Paused", "Stopped": resolvedIsPlaying = false
        default: resolvedIsPlaying = prev?.isPlaying ?? false
        }

        return NowPlayingSnapshot(
            title: nameField ?? prev?.title,
            artist: (info["Artist"] as? String) ?? prev?.artist,
            album: (info["Album"] as? String) ?? prev?.album,
            artwork: prev?.artwork,
            duration: durationMs > 0 ? durationMs / 1000 : prev?.duration ?? 0,
            elapsed: positionSec ?? prev?.elapsed ?? 0,
            elapsedAtSampleTime: Date(),
            isPlaying: resolvedIsPlaying
        )
    }

    private func fetchArtwork(from url: URL) {
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async {
                guard var current = self.snapshot else { return }
                current.artwork = image
                self.snapshot = current
                self.changesSubject.send()
            }
        }
        artworkFetchTask = task
        task.resume()
    }

    func send(_ command: NowPlayingCommand) {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next:      verb = "next track"
        case .previous:  verb = "previous track"
        }
        let source = "tell application \"Spotify\" to \(verb)"
        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                NSLog("[SpotifySource] %@ failed: %@", verb, error)
            }
        }
    }
}
