//
//  AXExistenceSource.swift
//  MacIsland
//
//  Lowest-fidelity NowPlayingSource. Only signal is "the macOS Now
//  Playing menu-bar widget currently exists in ControlCenter's menu
//  bar" — which is the system's own indicator that *something*,
//  somewhere, is playing audio.
//
//  This source covers everything the higher-fidelity Music.app /
//  Spotify / podcast bridges can't reach, most importantly browser
//  and PWA audio (YouTube, Spotify Web, Tidal, SoundCloud, …).
//
//  We can't read the track metadata at this layer — see the
//  experiment/ax-now-playing branch for the empirical proof. The
//  menu-bar element exposes only AXIdentifier="com.apple.menuextra.
//  now-playing" + AXDescription="Now Playing"; the real title /
//  artist / artwork live one level deeper inside a pop-over that
//  AX cannot reach without programmatically opening it (which
//  visibly flashes the pop-over on every refresh — not viable).
//
//  Manager priority (registration order LAST, fidelity .existence
//  LOWEST): when Music.app or Spotify also has data, those win and
//  this source is invisible. When they don't, this surfaces a
//  generic "Now Playing" chip so users get an iPhone-Dynamic-Island
//  style "something is playing" indicator instead of nothing.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

final class AXExistenceSource: NowPlayingSource {
    let identifier = "ax.existence"

    /// Existence-only — we have no way to drive transport from this
    /// signal. The view layer should hide playback controls when this
    /// is the active source.
    let controlsCapability: NowPlayingControls = .none

    private(set) var snapshot: NowPlayingSnapshot?

    private let changesSubject = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { changesSubject.eraseToAnyPublisher() }

    private var pollTimer: Timer?

    init() {
        // Trigger the AX TCC dialog on first launch. After the user
        // clicks "Open System Settings" and toggles MacIsland on in
        // Privacy → Accessibility, subsequent calls return true
        // without prompting again. If they decline, this source just
        // silently returns nil snapshots forever.
        let prompt = "AXTrustedCheckOptionPrompt"
        let opts = [prompt: kCFBooleanTrue!] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        NSLog("[AXExistenceSource] AX trust at launch: %@", trusted ? "true" : "false")

        // 3 s matches MusicAppSource's safety-net poll cadence —
        // anything faster wastes AX walks (which traverse the whole
        // ControlCenter menu bar each time), anything slower feels
        // laggy when a YouTube tab starts playing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    deinit {
        pollTimer?.invalidate()
    }

    func send(_ command: NowPlayingCommand) {
        // Existence-only source has no transport channel.
    }

    private func poll() {
        // AX queries hit another process (ControlCenter) and walk a
        // tree — push to a background queue so the run loop stays
        // responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let exists = AXExistenceSource.nowPlayingMenuExtraExists()
            DispatchQueue.main.async {
                self?.apply(exists: exists)
            }
        }
    }

    private func apply(exists: Bool) {
        if exists {
            // Already publishing existence — no need to re-emit on
            // every poll tick.
            if snapshot?.fidelity == .existence, snapshot?.isPlaying == true { return }
            snapshot = NowPlayingSnapshot(
                title: nil,
                artist: nil,
                album: nil,
                artwork: nil,
                duration: 0,
                elapsed: 0,
                elapsedAtSampleTime: Date(),
                isPlaying: true,
                fidelity: .existence
            )
            NSLog("[AXExistenceSource] system Now Playing widget detected")
            changesSubject.send()
        } else {
            if snapshot == nil { return }
            snapshot = nil
            NSLog("[AXExistenceSource] system Now Playing widget gone")
            changesSubject.send()
        }
    }

    /// Walk ControlCenter's menu bar items, return true iff one of
    /// them carries the `com.apple.menuextra.now-playing` identifier.
    /// Returns false on any error path (AX trust not granted,
    /// ControlCenter not running, AX call failure) — callers don't
    /// need to distinguish "nothing playing" from "we can't read";
    /// both yield no chip.
    private static func nowPlayingMenuExtraExists() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let cc = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.apple.controlcenter")
            .first
        else {
            return false
        }

        let app = AXUIElementCreateApplication(cc.processIdentifier)

        // ControlCenter exposes its menu bar via `AXChildren[0]` on
        // macOS 13+. The probe in experiment/ax-now-playing confirmed
        // this layout: app -> first child is the menu bar, whose
        // children are the AXMenuBarItem entries we want.
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let appChildren = childrenRef as? [AXUIElement]
        else {
            return false
        }

        for candidate in appChildren {
            var roleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &roleRef) == .success,
                  let role = roleRef as? String,
                  role == "AXMenuBar"
            else { continue }

            var itemsRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(candidate, kAXChildrenAttribute as CFString, &itemsRef) == .success,
                  let items = itemsRef as? [AXUIElement]
            else { continue }

            for item in items {
                var idRef: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, "AXIdentifier" as CFString, &idRef) == .success,
                      let id = idRef as? String
                else { continue }
                if id == "com.apple.menuextra.now-playing" {
                    return true
                }
            }
        }

        return false
    }
}
