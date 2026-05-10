//
//  DynamicIslandView.swift
//  MacIsland
//
//  Created by Ravindra Singh on 10/08/24.
//

import SwiftUI

struct DynamicIslandView: View {
    @StateObject var vm: DynamicIslandViewModel
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var nowPlayingManager: NowPlayingManager

    @State var dropTargeting: Bool = false
    /// Visibility flag for the charging chip. Set true on plug-in and
    /// auto-dismissed 5s later (transition-notification model — see
    /// the .batteryChargeStateChanged subscriber) so it doesn't block
    /// the music chip during continuous AC operation.
    @State private var showChargingPop = false
    /// Increments every charge-state notification so a stale dismiss
    /// timer (e.g. the 5s plug-in dismiss) becomes a no-op when the
    /// user unplugs early or replugs.
    @State private var chargingPopToken = 0
    /// Sticky-while-playing mirror of `nowPlayingManager.isPlaying`.
    /// Stays visible for the entire playback duration; dissolves out
    /// ~0.5s after playback stops to match the charging chip's feel.
    @State private var showMusicPop = false

    init(
        vm: DynamicIslandViewModel,
        batteryManager: BatteryManager,
        nowPlayingManager: NowPlayingManager
    ) {
        _vm = StateObject(wrappedValue: vm)
        self.batteryManager = batteryManager
        self.nowPlayingManager = nowPlayingManager
        _showChargingPop = State(initialValue: batteryManager.isCharging)
        _showMusicPop = State(initialValue: nowPlayingManager.isPlaying)
    }

    /// Which (if any) chip-style indicator is currently shown above the
    /// closed/popping notch. Charging takes priority over music — only
    /// one indicator is visible at a time.
    private enum VisibleChip { case none, charging, music }
    private var visibleChip: VisibleChip {
        guard vm.status != .opened else { return .none }
        if showChargingPop { return .charging }
        if showMusicPop { return .music }
        return .none
    }

    var notchSize: CGSize {
        switch vm.status {
        case let status where status != .opened && visibleChip != .none:
            return vm.notchChargingSize
        case .closed:
            var ans = CGSize(
                width: vm.deviceNotchRect.width - 4,
                height: vm.deviceNotchRect.height - 4
            )
            if ans.width < 0 { ans.width = 0 }
            if ans.height < 0 { ans.height = 0 }
            return ans
        case .opened:
            return vm.notchOpenedSize
        case .popping:
            return .init(
                width: visibleChip != .none ? 280 : vm.deviceNotchRect.width,
                height: vm.deviceNotchRect.height
            )
        }
    }

    var notchCornerRadius: CGFloat {
        switch vm.status {
        case .closed: 8
        case .opened: 32
        case .popping: 10
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            notch
                .zIndex(0)
                .disabled(true)
                .opacity(vm.notchVisible || visibleChip != .none ? 1 : 0.3)
            Group {
                switch visibleChip {
                case .charging:
                    ChargingPopView(batteryManager: batteryManager)
                        .transition(.expandWidth.combined(with: .opacity))
                        .zIndex(1)
                case .music:
                    MusicPopView(nowPlayingManager: nowPlayingManager)
                        .transition(.expandWidth.combined(with: .opacity))
                        .zIndex(1)
                case .none:
                    EmptyView()
                }
            }
            Group {
                if vm.status == .opened {
                    VStack(spacing: vm.spacing) {
                        DynamicIslandHeaderView(vm: vm)
                        DynamicIslandContentView(
                            vm: vm,
                            batteryManager: batteryManager,
                            nowPlayingManager: nowPlayingManager
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(vm.spacing)
                    .frame(maxWidth: vm.notchOpenedSize.width, maxHeight: vm.notchOpenedSize.height)
                    .zIndex(2)
                }
            }
            .transition(
                .scale.combined(
                    with: .opacity
                ).combined(
                    with: .offset(y: -vm.notchOpenedSize.height / 2)
                ).animation(vm.animation)
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .batteryChargeStateChanged)) { notif in
            if vm.status != .closed { return }

            if (notif.object as? Bool ?? false) {
                // Plugged in. Show the charging chip briefly, then
                // auto-dismiss after 5s — the chip is a *transition*
                // notification (you just plugged in), not a permanent
                // "device is charging" indicator. Otherwise it would
                // sit on the notch indefinitely and prevent the music
                // chip from showing while playing audio on AC power.
                // Matches iPhone Dynamic Island behaviour.
                chargingPopToken += 1
                let token = chargingPopToken
                withAnimation(.spring()) { showChargingPop = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    guard token == chargingPopToken else { return }
                    withAnimation(.spring()) { showChargingPop = false }
                }
            } else {
                // Unplugged. Show very briefly so the user sees the
                // state-change confirmation, then dismiss. Token
                // bumped so any stale 5s plug-in dismiss doesn't fight
                // this one.
                chargingPopToken += 1
                let token = chargingPopToken
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    guard token == chargingPopToken else { return }
                    withAnimation(.spring()) { showChargingPop = false }
                }
            }
        }
        .onReceive(nowPlayingManager.$isPlaying) { playing in
            // Mirror the charging-chip pattern: snap visible when playback
            // starts, dissolve out ~0.5s after it stops so a quick pause
            // doesn't flicker the chip out and back in.
            guard vm.status == .closed else { return }
            if playing {
                withAnimation(.spring()) { showMusicPop = true }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if !nowPlayingManager.isPlaying {
                        withAnimation(.spring()) { showMusicPop = false }
                    }
                }
            }
        }
        .animation(vm.animation, value: visibleChip)
        .background(dragDetector)
        .animation([.opened, .popping].contains(vm.status) ? vm.animation : .interactiveSpring(
            duration: 0.5,
            extraBounce: 0.01,
            blendDuration: 0.125
        ), value: vm.status)
        .preferredColorScheme(.dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var notch: some View {
        Rectangle()
            .foregroundStyle(.black)
            .mask(notchBackgroundMaskGroup)
            .frame(
                width: notchSize.width + notchCornerRadius * 2,
                height: notchSize.height
            )
            .shadow(
                color: .black.opacity(([.opened, .popping].contains(vm.status)) ? 1 : 0),
                radius: 16
            )
    }
    
    var notchBackgroundMaskGroup: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(
                width: notchSize.width,
                height: notchSize.height
            )
            .clipShape(.rect(
                bottomLeadingRadius: notchCornerRadius,
                bottomTrailingRadius: notchCornerRadius
            ))
            .overlay {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topLeadingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: notchCornerRadius + vm.spacing - 0.5, y: -0.5)
            }
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .frame(width: notchCornerRadius, height: notchCornerRadius)
                        .foregroundStyle(.black)
                    Rectangle()
                        .clipShape(.rect(topTrailingRadius: notchCornerRadius))
                        .foregroundStyle(.white)
                        .frame(
                            width: notchCornerRadius + vm.spacing,
                            height: notchCornerRadius + vm.spacing
                        )
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -notchCornerRadius - vm.spacing + 0.5, y: -0.5)
            }
    }

    @ViewBuilder
    var dragDetector: some View {
        RoundedRectangle(cornerRadius: notchCornerRadius)
            .foregroundStyle(Color.black.opacity(0.001)) // fuck you apple and 0.001 is the smallest we can have
            .contentShape(Rectangle())
            .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
            .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
            .onChange(of: dropTargeting) {
                if dropTargeting, vm.status == .closed {
                    // Open the notch when a file is dragged over it
                    vm.notchOpen(.drag)
                    vm.hapticSender.send()
                } else if !dropTargeting {
                    // Close the notch when the dragged item leaves the area
                    let mouseLocation: NSPoint = NSEvent.mouseLocation
                    if !vm.notchOpenedRect.insetBy(dx: vm.inset, dy: vm.inset).contains(mouseLocation) {
                        vm.notchClose()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

