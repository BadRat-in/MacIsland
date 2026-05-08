//
//  AXNowPlayingProbe.swift
//  MacIsland
//
//  Diagnostic-only Accessibility walker. Goal: empirically determine
//  whether the macOS Now Playing data is reachable from a third-party
//  app via AXUIElement on macOS 26 — and if so, by what attribute path.
//
//  How macOS exposes Now Playing in the menu bar:
//    - macOS 13+: the icon and pop-over live in the `com.apple.controlcenter`
//      process; menu-bar extras hang off its windows / children.
//    - Older macOS: same content lived in `com.apple.systemuiserver`.
//
//  This file walks both candidate processes and dumps every interesting
//  AX attribute (Role / Subrole / Title / Value / Description /
//  Identifier / Label) for every element down to a depth of 7. Output
//  goes to NSLog, which the freopen redirect in main.swift sends to
//  /tmp/macisland-debug.log. After a probe pass with music playing
//  the log will tell us:
//
//    1. Whether AX Trust was granted (without it, every read here is
//       silently null'd — same failure mode as MediaRemote).
//    2. Whether the Now Playing widget is in either process's UI tree
//       at all (some macOS versions hide menu-bar extras from
//       third-party AX clients).
//    3. Which attribute path actually carries the song title / artist
//       / artwork.
//
//  This is throw-away code in the sense that the production source
//  (when we build one) reads only the specific attributes we discover
//  here. Keep this file checked in so future macOS versions can be
//  re-probed cheaply if the layout changes.
//

import AppKit
import ApplicationServices

enum AXNowPlayingProbe {
    /// Bundle identifiers of the processes that historically host the
    /// Now Playing menu-bar extra. We probe both to handle differences
    /// between macOS major versions.
    private static let candidateBundleIDs = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
    ]

    /// Maximum recursion depth for the AX tree walker. Most menu-bar
    /// extras are shallow (3-4 levels); 7 gives us margin without
    /// risking runaway recursion on a pathological hierarchy.
    private static let maxDepth = 7

    /// Attributes worth dumping for every element. Anything carrying
    /// the song title or artist will surface in one of these.
    private static let interestingAttributes = [
        "AXRole",
        "AXSubrole",
        "AXRoleDescription",
        "AXTitle",
        "AXValue",
        "AXDescription",
        "AXIdentifier",
        "AXLabel",
        "AXHelp",
        "AXSelectedText",
    ]

    /// Triggers the Accessibility TCC prompt if not yet granted. After
    /// the user clicks "Open System Settings" and toggles MacIsland on
    /// in Privacy → Accessibility, subsequent calls return true without
    /// the prompt. Returns false until then.
    @discardableResult
    static func ensureTrusted() -> Bool {
        let prompt = "AXTrustedCheckOptionPrompt"
        let opts = [prompt: kCFBooleanTrue!] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        NSLog("[AXProbe] AXIsProcessTrusted: %@", trusted ? "true" : "false")
        return trusted
    }

    /// Run one full probe pass — identifies the candidate processes,
    /// walks each, dumps everything to NSLog. Cheap to call; safe to
    /// schedule on a timer for "watch what changes when the user starts
    /// playing music" diagnostics.
    static func runOnce() {
        guard ensureTrusted() else {
            NSLog("[AXProbe] Skipping probe — AX trust not granted yet.")
            return
        }

        for bundleID in candidateBundleIDs {
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            guard let app = matches.first else {
                NSLog("[AXProbe] %@ not running", bundleID)
                continue
            }
            probeApp(bundleID: bundleID, pid: app.processIdentifier)
        }
    }

    private static func probeApp(bundleID: String, pid: pid_t) {
        let appElement = AXUIElementCreateApplication(pid)
        NSLog("[AXProbe] === %@ (pid %d) — root attributes ===", bundleID, pid)
        logElement(appElement, depth: 0, label: "app")

        // Dive into menuBar, windows, children — three independent
        // entry points because different macOS versions surface menu
        // bar extras differently. ControlCenter on 13+ exposes them
        // via its windows; SystemUIServer used to attach them as
        // direct children.
        for entryAttribute in [kAXMenuBarAttribute, kAXWindowsAttribute, kAXChildrenAttribute] {
            walkAttribute(of: appElement, named: entryAttribute, label: "\(bundleID)/\(entryAttribute)")
        }
    }

    private static func walkAttribute(of element: AXUIElement, named attribute: String, label: String) {
        var ref: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
        guard err == .success else {
            NSLog("[AXProbe] %@ -> err %d", label, err.rawValue)
            return
        }
        guard let value = ref else {
            NSLog("[AXProbe] %@ -> nil", label)
            return
        }

        // The attribute may be a single AXUIElement or an array.
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            // swiftlint:disable:next force_cast
            walkTree(value as! AXUIElement, depth: 0, label: label)
        } else if let array = value as? [AXUIElement] {
            for (i, child) in array.enumerated() {
                walkTree(child, depth: 0, label: "\(label)[\(i)]")
            }
        } else {
            NSLog("[AXProbe] %@ -> %@", label, String(describing: value))
        }
    }

    private static func walkTree(_ element: AXUIElement, depth: Int, label: String) {
        guard depth < maxDepth else { return }

        // If this is the Now Playing menu extra, ALWAYS do the full
        // attribute dump — it's the entire reason this probe exists.
        var idRef: CFTypeRef?
        let isNowPlaying = AXUIElementCopyAttributeValue(
            element,
            "AXIdentifier" as CFString,
            &idRef
        ) == .success && (idRef as? String)?.contains("now-playing") == true

        logElement(element, depth: depth, label: label, forceFullDump: isNowPlaying)

        var childrenRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        guard err == .success, let children = childrenRef as? [AXUIElement] else { return }
        for (i, child) in children.enumerated() {
            walkTree(child, depth: depth + 1, label: "\(label)/\(i)")
        }
    }

    private static func logElement(
        _ element: AXUIElement,
        depth: Int,
        label: String,
        forceFullDump: Bool = false
    ) {
        let indent = String(repeating: "  ", count: depth)

        // First: the curated short-list (so the log stays scannable
        // for the common case).
        var pieces: [String] = []
        for attribute in interestingAttributes {
            var ref: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &ref)
            guard err == .success, let value = ref else { continue }
            let stringified = stringify(value)
            guard !stringified.isEmpty else { continue }
            pieces.append("\(attribute)=\(stringified)")
        }
        if !pieces.isEmpty {
            NSLog("[AXProbe] %@%@ — %@", indent, label, pieces.joined(separator: " "))
        }

        // Second: the FULL attribute name list. We dump this when the
        // element is anonymous (no Description / Identifier / Title)
        // OR when forceFullDump asks for it (Now Playing widget — the
        // whole point of this probe).
        let looksAnonymous = pieces.allSatisfy {
            !$0.starts(with: "AXIdentifier")
                && !$0.starts(with: "AXDescription")
                && !$0.starts(with: "AXTitle")
        }
        guard looksAnonymous || forceFullDump else { return }

        var namesRef: CFArray?
        let err = AXUIElementCopyAttributeNames(element, &namesRef)
        if err == .success, let names = namesRef as? [String] {
            NSLog("[AXProbe] %@%@   ALL_ATTRS=%@", indent, label, names.description)
            for name in names {
                var ref: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
                   let value = ref {
                    let s = stringify(value)
                    if !s.isEmpty, s != "()", s != "<null>" {
                        NSLog("[AXProbe] %@%@     %@=%@", indent, label, name, s)
                    }
                }
            }
        } else {
            NSLog("[AXProbe] %@%@   AXUIElementCopyAttributeNames err=%d", indent, label, err.rawValue)
        }
    }

    private static func stringify(_ value: CFTypeRef) -> String {
        if let s = value as? String {
            // Truncate long values so a 50KB AX text blob doesn't blow
            // up the log.
            return "\"\(s.prefix(160))\""
        }
        if let n = value as? NSNumber { return n.stringValue }
        if let b = value as? Bool { return b ? "true" : "false" }
        return String(describing: value).prefix(160).description
    }
}
