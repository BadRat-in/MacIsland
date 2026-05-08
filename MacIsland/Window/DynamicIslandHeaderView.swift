//
//  DynamicIslandHeaderView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import ColorfulX
import SwiftUI

struct DynamicIslandHeaderView: View {
    @StateObject var vm: DynamicIslandViewModel

    var body: some View {
        HStack {
            Text(
                vm.contentType == .settings
                    ? "Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))"
                    : ""
            )
            .contentTransition(.numericText())
            Spacer()
            Image(systemName: "ellipsis")
        }
        .animation(vm.animation, value: vm.contentType)
        .font(.system(.headline, design: .rounded))
    }
}

#Preview {
    DynamicIslandHeaderView(vm: .init())
}

