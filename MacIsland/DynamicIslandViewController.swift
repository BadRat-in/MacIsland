//
//  DynamicIslandViewController.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import AppKit
import Cocoa
import SwiftUI

class DynamicIslandViewController: NSHostingController<DynamicIslandView> {
    init(_ vm: DynamicIslandViewModel, batteryManager: BatteryManager) {
        super.init(rootView: DynamicIslandView(vm: vm, batteryManager: batteryManager))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}

