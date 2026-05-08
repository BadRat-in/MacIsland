//
//  AppDelegate.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import AppKit
import Cocoa
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
    var isFirstOpen = true
    var isLaunchedAtLogin = false
    var mainWindowController: DynamicIslandWindowController?

    /// System-state observers live for the lifetime of the process —
    /// they listen to DNC / IOKit notifications that have nothing to
    /// do with which screen the notch is drawn on. Keeping them up
    /// here rather than inside DynamicIslandWindowController means a
    /// `didChangeScreenParametersNotification` (which fires on focus
    /// changes, full-screen toggles, display sleep, etc.) doesn't
    /// destroy and recreate them — previously that wiped now-playing
    /// state and caused the music chip to disappear and re-appear
    /// after the safety-net poll caught up.
    let batteryManager = BatteryManager()
    let nowPlayingManager = NowPlayingManager()

    var timer: Timer?
    /// Held for the lifetime of the process to keep the App Nap policy
    /// from suspending us while idle. We listen to system-wide
    /// DistributedNotificationCenter events (charging, music) and
    /// poll Music.app every 3s, neither of which the OS knows we
    /// care about — without this token, the chip can stop updating
    /// after a long idle window.
    private var noNapToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_: Notification) {
        noNapToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated],
            reason: "Watching media playback + battery state"
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildApplicationWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSApp.setActivationPolicy(.accessory)

        isLaunchedAtLogin = LaunchAtLogin.wasLaunchedAtLogin

        _ = EventMonitors.shared
        let timer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true
        ) { [weak self] _ in
            self?.determineIfProcessIdentifierMatches()
            self?.makeKeyAndVisibleIfNeeded()
        }
        self.timer = timer

        rebuildApplicationWindows()

        // Diagnostic-only Accessibility probe — investigates whether
        // the macOS Now Playing widget can be read via AX on this
        // version of macOS. First call triggers the AX TCC prompt.
        // Re-runs every 5s so the user can play / pause / skip a
        // track after granting permission and we observe how the
        // surfaced AX attributes change. Output: /tmp/macisland-debug.log.
        AXNowPlayingProbe.runOnce()
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            AXNowPlayingProbe.runOnce()
        }
    }

    func applicationWillTerminate(_: Notification) {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        try? FileManager.default.removeItem(at: pidFile)
    }

    func findScreenFitsOurNeeds() -> NSScreen? {
         if let screen = NSScreen.buildin, screen.notchSize != .zero { return screen }
         return .main
     }

    @objc func rebuildApplicationWindows() {
        let newScreen = findScreenFitsOurNeeds()

        // didChangeScreenParametersNotification is over-eager: it
        // fires on dock visibility changes, app focus shifts,
        // full-screen toggles, and minimize/restore of *other*
        // apps — none of which actually change which screen we
        // want our notch on. Each blind rebuild tore the window
        // down and recreated it, flashing the chip out + in for
        // ~50-100ms (the "trying to hide / pushed back" wobble
        // the user reported on minimize/restore). Skip the
        // rebuild when the target screen hasn't actually changed.
        if !isFirstOpen,
           let existing = mainWindowController,
           let existingScreen = existing.screen,
           let target = newScreen,
           Self.screensMatch(existingScreen, target) {
            NSLog("[AppDelegate] rebuildApplicationWindows skipped — same screen")
            return
        }
        NSLog("[AppDelegate] rebuildApplicationWindows running")

        defer { isFirstOpen = false }
        if let mainWindowController {
            mainWindowController.destroy()
        }

        mainWindowController = nil
        guard let mainScreen = newScreen else { return }
        mainWindowController = .init(
            screen: mainScreen,
            batteryManager: batteryManager,
            nowPlayingManager: nowPlayingManager
        )
        if isFirstOpen, !isLaunchedAtLogin {
            mainWindowController?.openAfterCreate = true
        }
    }

    /// Compare two NSScreens by display ID — the system can hand us
    /// a fresh `NSScreen` instance describing the same physical
    /// display after a screen-parameters notification, so reference
    /// equality is unreliable.
    private static func screensMatch(_ a: NSScreen, _ b: NSScreen) -> Bool {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        let lhs = a.deviceDescription[key] as? NSNumber
        let rhs = b.deviceDescription[key] as? NSNumber
        return lhs != nil && lhs == rhs
    }

    func determineIfProcessIdentifierMatches() {
        let pid = String(NSRunningApplication.current.processIdentifier)
        let content = (try? String(contentsOf: pidFile)) ?? ""
        guard pid.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        else {
            NSApp.terminate(nil)
            return
        }
    }

    func makeKeyAndVisibleIfNeeded() {
        guard let controller = mainWindowController,
              let window = controller.window,
              let vm = controller.vm,
              vm.status == .opened
        else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let controller = mainWindowController,
              let vm = controller.vm
        else { return true }
        vm.notchOpen(.click)
        return true
    }
}
