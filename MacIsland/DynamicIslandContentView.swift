//
//  DynamicIslandContentView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import SwiftUI
import ColorfulX
import Pow
import UniformTypeIdentifiers

struct DynamicIslandContentView: View {
    @StateObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var nowPlayingManager: NowPlayingManager

    @State var hover: Bool = false
    @State var trigger: UUID = .init()
    @State var targeting = false

    /// `.normal` is context-aware: when a track is playing and the user
    /// hasn't tapped Home, it shows MusicView. Otherwise it shows the
    /// AirDrop / TrayDrop / Battery row.
    private var showMusicAsDefault: Bool {
        !vm.preferHomeOverMusic && nowPlayingManager.hasTrack
    }

    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                if showMusicAsDefault {
                    MusicView(vm: vm, nowPlayingManager: nowPlayingManager)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                } else {
                    HStack(spacing: vm.spacing) {
                        AirDropView(vm: vm)
                        TrayView(vm: vm)
                        if batteryManager.hasBattery() {
                            BatteryView(batteryManager: batteryManager)
                        }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            case .menu:
                DynamicIslandMenuView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .settings:
                DynamicIslandSettingsView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .dropTray:
                TrayView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .music:
                MusicView(vm: vm, nowPlayingManager: nowPlayingManager)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(vm.animation, value: vm.contentType)
        .animation(vm.animation, value: showMusicAsDefault)
    }
    
    var dropLabel: some View {
        ColorButton(
            cornerRadius: vm.cornerRadius,
            color: ColorfulPreset.colorful.colors,
            image: Image(systemName: "tray.and.arrow.down.fill"),
            title: LocalizedStringKey("DropTray")
        ).onTapGesture {
            vm.openDropTray()
        }
    }
}



#Preview {
    DynamicIslandContentView(
        vm: .init(),
        batteryManager: BatteryManager(),
        nowPlayingManager: NowPlayingManager()
    )
    .padding()
    .frame(width: 600, height: 150, alignment: .center)
    .background(.black)
    .preferredColorScheme(.dark)
}

