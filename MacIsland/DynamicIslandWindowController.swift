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
    var batteryManager: BatteryManager?
    weak var screen: NSScreen?

    var openAfterCreate: Bool = false

    init(window: NSWindow, screen: NSScreen) {
        self.screen = screen

        super.init(window: window)

        var notchSize = screen.notchSize

        let vm = DynamicIslandViewModel(inset: notchSize == .zero ? 0 : -4)
        self.vm = vm
        let batteryManager = BatteryManager()
        self.batteryManager = batteryManager
        contentViewController = DynamicIslandViewController(vm, batteryManager: batteryManager)

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

    convenience init(screen: NSScreen) {
        let window = DynamicIslandWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        self.init(window: window, screen: screen)

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
        window?.close()
        contentViewController = nil
        window = nil
    }
}

