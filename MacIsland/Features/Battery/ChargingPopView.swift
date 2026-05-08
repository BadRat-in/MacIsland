//
//  ChargingPopView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 18/08/25.
//

import SwiftUI

struct ChargingPopView: View {
    @ObservedObject var batteryManager: BatteryManager
    
    var body: some View {
        HStack {
            // Left side: Battery Icon
            batteryIcon(for: batteryManager.percentage, charging: batteryManager.isCharging)
                .font(.title2)
                .frame(alignment: .leading)
            
            Spacer()

            // Right side: Percentage + Text
            Text("\(batteryManager.percentage)%")
                .font(.headline)
                .foregroundColor(.primary)
                .frame(alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .preferredColorScheme(.dark)
        .shadow(radius: 4)
        .frame(maxWidth: 275) // keep it notch-like
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: batteryManager.percentage)
    }
    
    
    
    private func batteryIcon(for percentage: Int, charging: Bool) -> some View {
        let level: Int
        switch percentage {
        case 0..<10:
            level = 0
        case 10..<40:
            level = 25
        case 40..<70:
            level = 50
        case 70..<90:
            level = 75
        default:
            level = 100
        }

        return ZStack {
            Image(systemName: "battery.\(level)")
                .foregroundStyle(batteryManager.isCharging ? .green : percentage <= 20 ? .red : .primary, batteryManager.isCharging ? .green : .primary)
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
        }
    }
}

#Preview {
    ChargingPopView(batteryManager: BatteryManager())
}
