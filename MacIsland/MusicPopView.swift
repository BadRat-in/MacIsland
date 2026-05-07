//
//  MusicPopView.swift
//  MacIsland
//
//  Compact "now playing" chip shown briefly on track change. Layout
//  mirrors ChargingPopView: visual indicator (artwork) on the left,
//  numeric (remaining time) on the right.
//

import SwiftUI

struct MusicPopView: View {
    @ObservedObject var nowPlayingManager: NowPlayingManager

    var body: some View {
        HStack {
            artwork
                .frame(alignment: .leading)

            Spacer()

            Text(remainingTimeString)
                .font(.headline)
                .foregroundColor(.primary)
                .monospacedDigit()
                .frame(alignment: .trailing)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 8)
        .preferredColorScheme(.dark)
        .shadow(radius: 4)
        .frame(maxWidth: 275)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: nowPlayingManager.title)
    }

    private var artwork: some View {
        Group {
            if let image = nowPlayingManager.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().foregroundStyle(.white.opacity(0.1))
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var remainingTimeString: String {
        let total = max(nowPlayingManager.duration, 0)
        let elapsed = max(min(nowPlayingManager.elapsed, total), 0)
        let remaining = max(total - elapsed, 0)
        // No duration available yet — show a placeholder rather than 0:00.
        guard total > 0 else { return "--:--" }
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "-%d:%02d", mins, secs)
    }
}

#Preview {
    MusicPopView(nowPlayingManager: NowPlayingManager())
        .frame(width: 280, height: 32)
        .background(.black)
}
