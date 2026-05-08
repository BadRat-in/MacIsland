//
//  SystemVolume.swift
//  MacIsland
//
//  Read and write the macOS system output volume — the same value
//  the keyboard volume keys move and that the Sound preference pane
//  shows. Decoupled from MusicAppBridge so the slider works whether
//  or not Music.app is running.
//
//  AppleScript's `output volume of (get volume settings)` returns
//  a 0–100 Int; `set volume output volume N` accepts the same range.
//  No additional permissions beyond Automation TCC (which we already
//  have for Music.app).
//

import Foundation

enum SystemVolume {
    /// Current macOS output volume on a 0–100 scale, or nil if the
    /// AppleScript call failed for any reason.
    static func current() -> Double? {
        let source = "output volume of (get volume settings)"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if error != nil { return nil }
        let value = result?.doubleValue ?? -1
        return value >= 0 ? value : nil
    }

    /// Set system output volume on a 0–100 scale. Async — runs the
    /// AppleScript on a background queue so callers don't block the
    /// main thread on the AS round-trip.
    static func set(_ value: Double) {
        let clamped = max(0, min(100, Int(value.rounded())))
        let source = "set volume output volume \(clamped)"
        DispatchQueue.global(qos: .userInitiated).async {
            NSAppleScript(source: source)?.executeAndReturnError(nil)
        }
    }
}
