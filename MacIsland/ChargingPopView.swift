//
//  ChargingPopView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 18/08/25.
//

import SwiftUI

struct ChargingPopView: View {
    let percentage: Int
    let charging: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            batteryIcon(for: percentage,
                        charging: charging)
                .foregroundColor(charging ? .green : .primary)
                .font(.title2)
            
            if charging {
                Text("\(percentage)% " + NSLocalizedString("Charging", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
            } else {
                Text("\(percentage)% " + NSLocalizedString("Charged", comment: ""))
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 5)
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
