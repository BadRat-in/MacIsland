//
//  DynamicIslandMenuView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//


import ColorfulX
import SwiftUI

struct DynamicIslandMenuView: View {
    @StateObject var vm: DynamicIslandViewModel
    @StateObject var tvm = TrayDrop.shared

    var body: some View {
        HStack(spacing: vm.spacing) {
            close
            music
            settings
            clear
        }
    }

    var music: some View {
        ColorButton(
            cornerRadius: 5,
            color: ColorfulPreset.appleIntelligence.colors,
            image: Image(systemName: "music.note"),
            title: LocalizedStringKey("Music")
        )
        .onTapGesture {
            vm.openMusic()
        }
        .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadius))
    }

    var close: some View {
        ColorButton(
            cornerRadius: 5,
            color: [.red],
            image: Image(systemName: "xmark"),
            title: "Exit"
        )
        .onTapGesture {
            vm.notchClose()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                NSApp.terminate(nil)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadius))
    }

    var clear: some View {
        ColorButton(
            cornerRadius: 5,
            color: [.red],
            image: Image(systemName: "trash"),
            title: "Clear"
        )
        .onTapGesture {
            tvm.removeAll()
            vm.notchClose()
        }
        .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadius))
    }

    var settings: some View {
        ColorButton(
            cornerRadius: 5,
            color: ColorfulPreset.colorful.colors,
            image: Image(systemName: "gear"),
            title: LocalizedStringKey("Settings")
        )
        .onTapGesture {
            vm.showSettings()
        }
        .clipShape(RoundedRectangle(cornerRadius: vm.cornerRadius))
    }
}

#Preview {
    DynamicIslandMenuView(vm: .init())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}

