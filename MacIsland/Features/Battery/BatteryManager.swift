//
//  Battery.swift
//  MacIsland
//
//  Created by Ravindra Singh on 18/08/25.
//

import SwiftUI
import IOKit.ps

class BatteryManager: ObservableObject {
    private var lastPowerState: String? = nil
    @Published var timeRemaining: String = ""
    @Published var percentage: Int = 0
    @Published var isCharging: Bool = false {
        didSet {
            if isCharging != oldValue {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .batteryChargeStateChanged,
                        object: self.isCharging
                    )
                }
            }
        }
    }
    
    init() {
        updateBatteryStatus()
        
        // Poll every 60s as fallback
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            self.updateBatteryStatus()
        }

        // Register for live power source change events
        if let runLoopSource = IOPSNotificationCreateRunLoopSource({ context in
            let manager = Unmanaged<BatteryManager>.fromOpaque(context!).takeUnretainedValue()
            manager.updateBatteryStatus()
        }, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .defaultMode)
        }
    }
    
    private func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources: NSArray = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            return
        }

        for ps in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, ps as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            if let capacity = info[kIOPSCurrentCapacityKey] as? Int,
               let max = info[kIOPSMaxCapacityKey] as? Int {
                self.percentage = Int((Double(capacity) / Double(max)) * 100)
            }

            if let state = info[kIOPSPowerSourceStateKey] as? String {
                self.isCharging = (state == kIOPSACPowerValue)
                handlePowerSourceChange(newState: state)
            }

            if isCharging {
                if let time = info[kIOPSTimeToFullChargeKey] as? Int, time > 0 {
                    self.timeRemaining = formatTime(minutes: time, suffix: NSLocalizedString("until full", comment: ""))
                } else if percentage == 100 {
                    self.timeRemaining = NSLocalizedString(("Charged"), comment: "")
                } else {
                    self.timeRemaining = ""
                }
            } else {
                if let time = info[kIOPSTimeToEmptyKey] as? Int, time > 0 {
                    self.timeRemaining = formatTime(minutes: time, suffix: NSLocalizedString("left", comment: ""))
                } else {
                    self.timeRemaining = ""
                }
            }
        }
    }
    
    // Fire notifications / events when charger state changes
    private func handlePowerSourceChange(newState: String) {
        if newState != lastPowerState {
            lastPowerState = newState
            let onAC = (newState == kIOPSACPowerValue)
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .batteryChargeStateChanged,
                    object: onAC // true = plugged in, false = unplugged
                )
                print("⚡️ Posted batteryChargeStateChanged: \(onAC)")
            }
        }
    }
    
    func hasBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources: NSArray = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() else {
            return false
        }

        for ps in sources {
            guard let info = IOPSGetPowerSourceDescription(snapshot, ps as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            if let type = info[kIOPSTransportTypeKey] as? String,
               type == kIOPSInternalType {
                return true // ✅ Found an internal battery
            }
        }
        return false
    }

    private func formatTime(minutes: Int, suffix: String) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let mins = minutes % 60
            if mins > 0 {
                return "\(hours)h \(mins)m \(suffix)"
            } else {
                return "\(hours)h \(suffix)"
            }
        } else {
            return "\(minutes)m \(suffix)"
        }
    }

}
