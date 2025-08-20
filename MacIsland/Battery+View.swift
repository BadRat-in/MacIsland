//
//  Battery+View.swift
//  MacIsland
//
//  Created by Ravindra Singh on 18/08/25.
//

import SwiftUI

struct BatteryView: View {
    @ObservedObject var batteryManager: BatteryManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                batteryIcon(for: batteryManager.percentage,
                            charging: batteryManager.isCharging)
                    .foregroundColor(batteryManager.isCharging ? .green : .primary)
                    .font(.system(size: 20))
                
                Text("\(batteryManager.percentage)%")
                    .font(.headline)
            }
            if !batteryManager.timeRemaining.isEmpty {
                Text(batteryManager.timeRemaining)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }

    private func batteryIcon(for percentage: Int, charging: Bool) -> some View {
        let level: String
        switch percentage {
        case 0..<20:
            level = "0"
        case 20..<40:
            level = "25"
        case 40..<70:
            level = "50"
        case 70..<90:
            level = "75"
        default:
            level = "100"
        }

        return ZStack {
            Image(systemName: "battery.\(level)")
            if charging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
            }
        }
    }
}
