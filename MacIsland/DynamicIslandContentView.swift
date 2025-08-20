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
    
    @State var hover: Bool = false
    @State var trigger: UUID = .init()
    @State var targeting = false
    
    var body: some View {
        ZStack {
            switch vm.contentType {
            case .normal:
                HStack(spacing: vm.spacing) {
                    AirDropView(vm: vm)
                    TrayView(vm: vm)
                    if batteryManager.hasBattery() {
                        BatteryView(batteryManager: batteryManager)
                    }
                    
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .menu:
                DynamicIslandMenuView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .settings:
                DynamicIslandSettingsView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            case .dropTray:
                TrayView(vm: vm)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .animation(vm.animation, value: vm.contentType)
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
    DynamicIslandMenuView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}

