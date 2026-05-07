//
//  MusicAppBridge.swift
//  MacIsland
//
//  AppleScript bridge to Music.app for the bits its DNC notification
//  doesn't include — artwork data, current playback position, the
//  full state snapshot we use for the safety-net poll, and volume.
//
//  First call prompts the user with the standard "MacIsland would like
//  to control Music" dialog (Automation TCC). If the user denies or
//  Music.app isn't running, every call here returns nil — never raises
//  to the caller — and we degrade silently rather than block the UI.
//

import AppKit
import Foundation

enum MusicAppBridge {
    /// Consolidated snapshot fetched in a single AppleScript call so
    /// the safety-net poll doesn't fan out to several round-trips.
    /// `artwork` is fetched in a separate call because returning binary
    /// data inside a list returns an awkward descriptor on some macOS
    /// versions; pulling it on its own is more reliable.
    struct Snapshot {
        let isPlaying: Bool
        let title: String?
        let artist: String?
        let album: String?
        let duration: TimeInterval
        let position: TimeInterval
        let volume: Double?
    }

    static func currentSnapshot() -> Snapshot? {
        let source = """
        tell application "Music"
            if it is running then
                try
                    set s to player state as text
                    if s is "stopped" then
                        return {"stopped", "", "", "", 0, 0, sound volume}
                    end if
                    set t to current track
                    return {s, (name of t) as text, (artist of t) as text, (album of t) as text, (duration of t), player position, sound volume}
                end try
            end if
            return missing value
        end tell
        """
        guard let descriptor = run(source: source),
              descriptor.numberOfItems >= 7 else { return nil }

        // descriptor.atIndex(_:) is 1-based; AppleScript lists are also 1-based.
        let stateString = descriptor.atIndex(1)?.stringValue?.lowercased() ?? ""
        let title = descriptor.atIndex(2)?.stringValue
        let artist = descriptor.atIndex(3)?.stringValue
        let album = descriptor.atIndex(4)?.stringValue
        let duration = descriptor.atIndex(5)?.doubleValue ?? 0
        let position = descriptor.atIndex(6)?.doubleValue ?? 0
        let volume = descriptor.atIndex(7)?.doubleValue

        let isPlaying = stateString == "playing"

        return Snapshot(
            isPlaying: isPlaying,
            title: title?.isEmpty == false ? title : nil,
            artist: artist?.isEmpty == false ? artist : nil,
            album: album?.isEmpty == false ? album : nil,
            duration: duration,
            position: position,
            volume: volume
        )
    }

    static func currentArtwork() -> NSImage? {
        let source = """
        tell application "Music"
            if it is running then
                try
                    return data of artwork 1 of current track
                end try
            end if
            return missing value
        end tell
        """
        guard let descriptor = run(source: source) else {
            NSLog("[MusicAppBridge] currentArtwork: nil descriptor (TCC denied or no track)")
            return nil
        }
        let data = descriptor.data
        guard !data.isEmpty else {
            NSLog("[MusicAppBridge] currentArtwork: empty data — track has no artwork")
            return nil
        }
        guard let image = NSImage(data: data) else {
            NSLog("[MusicAppBridge] currentArtwork: NSImage failed to parse %d bytes", data.count)
            return nil
        }
        NSLog("[MusicAppBridge] currentArtwork: %d bytes -> %.0fx%.0f",
              data.count, image.size.width, image.size.height)
        return image
    }

    static func setVolume(_ value: Double) {
        let clamped = max(0, min(100, Int(value.rounded())))
        let source = "tell application \"Music\" to set sound volume to \(clamped)"
        _ = run(source: source)
    }

    private static func run(source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743 == errAEEventNotPermitted (TCC denied / user said no).
            // -600 == application isn't running. Both are expected on
            // many launches — log once at debug level, don't escalate.
            NSLog("[MusicAppBridge] AppleScript error: %@", error)
            return nil
        }
        if result.descriptorType == typeNull { return nil }
        return result
    }
}
