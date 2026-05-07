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
        defer { isFirstOpen = false }
        if let mainWindowController {
            mainWindowController.destroy()
        }

        mainWindowController = nil
        guard let mainScreen = findScreenFitsOurNeeds() else { return }
        mainWindowController = .init(
            screen: mainScreen,
            batteryManager: batteryManager,
            nowPlayingManager: nowPlayingManager
        )
        if isFirstOpen, !isLaunchedAtLogin {
            mainWindowController?.openAfterCreate = true
        }
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
