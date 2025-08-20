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
    var mainWindowController: [DynamicIslandWindowController] = []

    var timer: Timer?

    func applicationDidFinishLaunching(_: Notification) {        
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

    func findScreenFitsOurNeeds() -> [NSScreen?] {
        var screens: [NSScreen?] = []
        if let screen = NSScreen.buildin, screen.notchSize != .zero { screens.append(screen) }
        screens.append(NSScreen.main)
        
        for screen in NSScreen.screens {
            if screens.contains(screen) { continue }
            screens.append(screen)
        }
        return screens
    }

    @objc func rebuildApplicationWindows() {
        defer { isFirstOpen = false }
        mainWindowController.forEach {
            $0.destroy()
        }

        for s in findScreenFitsOurNeeds() {
            guard let screen = s else { continue }
            print("Notch detected on \(String(describing: screen.notchSize))")
            let controller = DynamicIslandWindowController(screen: screen)
            mainWindowController.append(controller)
            if screen.notchSize != .zero , NSScreen.buildin == screen, isFirstOpen, !isLaunchedAtLogin {
                controller.openAfterCreate = true
            }
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
        guard let controller = mainWindowController.first,
              let window = controller.window,
              let vm = controller.vm,
              vm.status == .opened
        else { return }
        window.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        guard let controller = mainWindowController.first,
              let vm = controller.vm
        else { return true }
        vm.notchOpen(.click)
        return true
    }
}
