//
//  DynamicIslandWindowController.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import Cocoa

private let notchHeight: CGFloat = 200

class DynamicIslandWindowController: NSWindowController {
    var vm: DynamicIslandViewModel?
    /// Managers are owned by AppDelegate; we just hold references so
    /// they stick around for the lifetime of the content view. Don't
    /// release these in `destroy()` — the next window controller
    /// (rebuilt on screen-parameter change) wants the same instances
    /// with their accumulated state intact.
    private let batteryManager: BatteryManager
    private let nowPlayingManager: NowPlayingManager
    weak var screen: NSScreen?

    var openAfterCreate: Bool = false

    init(
        window: NSWindow,
        screen: NSScreen,
        batteryManager: BatteryManager,
        nowPlayingManager: NowPlayingManager
    ) {
        self.screen = screen
        self.batteryManager = batteryManager
        self.nowPlayingManager = nowPlayingManager

        super.init(window: window)

        var notchSize = screen.notchSize

        let vm = DynamicIslandViewModel(inset: notchSize == .zero ? 0 : -4)
        self.vm = vm
        contentViewController = DynamicIslandViewController(
            vm,
            batteryManager: batteryManager,
            nowPlayingManager: nowPlayingManager
        )

        if notchSize == .zero {
            notchSize = .init(width: 150, height: 28)
        }
        vm.deviceNotchRect = CGRect(
            x: screen.frame.origin.x + (screen.frame.width - notchSize.width) / 2,
            y: screen.frame.origin.y + screen.frame.height - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak vm] in
            vm?.screenRect = screen.frame
            if self.openAfterCreate { vm?.notchOpen(.boot) }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    convenience init(
        screen: NSScreen,
        batteryManager: BatteryManager,
        nowPlayingManager: NowPlayingManager
    ) {
        let window = DynamicIslandWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.init(
            window: window,
            screen: screen,
            batteryManager: batteryManager,
            nowPlayingManager: nowPlayingManager
        )

        let topRect = CGRect(
            x: screen.frame.origin.x,
            y: screen.frame.origin.y + screen.frame.height - notchHeight,
            width: screen.frame.width,
            height: notchHeight
        )
        window.setFrameOrigin(topRect.origin)
        window.setContentSize(topRect.size)
    }

    deinit {
        destroy()
    }

    func destroy() {
        vm?.destroy()
        vm = nil
        // Note: batteryManager and nowPlayingManager are deliberately
        // NOT released here — they're owned by AppDelegate and outlive
        // any single window-controller instance. Releasing them on
        // every screen-param-change rebuild was the cause of the
        // music chip vanishing on minimize/focus until the safety-net
        // poll rehydrated state.
        window?.close()
        contentViewController = nil
        window = nil
    }
}

