//
//  Music+View.swift
//  MacIsland
//
//  Expanded music panel shown when ContentType == .music. Read-only in
//  this PR — playback controls land in the follow-up PR.
//

import SwiftUI

struct MusicView: View {
    @StateObject var vm: DynamicIslandViewModel
    @ObservedObject var nowPlayingManager: NowPlayingManager

    var body: some View {
        if !nowPlayingManager.hasTrack {
            emptyState
        } else {
            playingState
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("Nothing playing", comment: ""))
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString(
                "Detection currently works for Music.app and Spotify. Browser audio (e.g. YouTube) and other apps are out of our control on macOS — we're tracking the limitation.",
                comment: "Shown in the music panel empty state to explain DNC-only detection."
            ))
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
        }
        .padding()
    }

    private var playingState: some View {
        HStack(spacing: vm.spacing) {
            artwork
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlayingManager.title ?? "")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                            .contentTransition(.opacity)
                        if let artist = nowPlayingManager.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                        if let album = nowPlayingManager.album, !album.isEmpty {
                            Text(album)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .contentTransition(.opacity)
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: nowPlayingManager.title)
                    Spacer(minLength: 0)
                    homeButton
                }
                Spacer(minLength: 0)
                progressRow
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
    }

    private var progressRow: some View {
        HStack(spacing: 8) {
            Text(formatTime(nowPlayingManager.elapsed))
                .font(.system(.caption2, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: nowPlayingManager.elapsed)
            progressBar
            Text(formatRemaining())
                .font(.system(.caption2, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: nowPlayingManager.elapsed)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func formatRemaining() -> String {
        let total = max(nowPlayingManager.duration, 0)
        guard total > 0 else { return "--:--" }
        let elapsed = max(min(nowPlayingManager.elapsed, total), 0)
        let remaining = max(total - elapsed, 0)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        return String(format: "-%d:%02d", mins, secs)
    }

    private var homeButton: some View {
        Button {
            vm.showHome()
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(6)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("Show app home", comment: ""))
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Spacer()
            controlButton(systemImage: "backward.fill", size: 16) {
                nowPlayingManager.send(.previous)
            }
            .help(NSLocalizedString("Previous track", comment: ""))
            controlButton(
                systemImage: nowPlayingManager.isPlaying ? "pause.fill" : "play.fill",
                size: 20
            ) {
                nowPlayingManager.send(.playPause)
            }
            .help(NSLocalizedString("Play / Pause", comment: ""))
            controlButton(systemImage: "forward.fill", size: 16) {
                nowPlayingManager.send(.next)
            }
            .help(NSLocalizedString("Next track", comment: ""))
            volumeControl
            Spacer()
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 4) {
            Image(systemName: speakerIconName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Slider(
                value: Binding(
                    get: { nowPlayingManager.volume },
                    set: { nowPlayingManager.setVolume($0) }
                ),
                in: 0...100
            )
            .frame(width: 70)
            .controlSize(.mini)
            .tint(.white.opacity(0.85))
        }
        .padding(.leading, 8)
    }

    private var speakerIconName: String {
        switch nowPlayingManager.volume {
        case ..<1: return "speaker.slash.fill"
        case ..<33: return "speaker.wave.1.fill"
        case ..<66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func controlButton(
        systemImage: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var artwork: some View {
        Group {
            if let image = nowPlayingManager.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .id(nowPlayingManager.title ?? "")
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                ZStack {
                    Rectangle().foregroundStyle(.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeInOut(duration: 0.35), value: nowPlayingManager.title)
        .animation(.easeInOut(duration: 0.25), value: nowPlayingManager.artwork != nil)
    }

    private var progressBar: some View {
        let total = max(nowPlayingManager.duration, 0.001)
        let progress = min(max(nowPlayingManager.elapsed / total, 0), 1)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .foregroundStyle(.white.opacity(0.15))
                Capsule()
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    MusicView(vm: .init(), nowPlayingManager: NowPlayingManager())
        .padding()
        .frame(width: 600, height: 150, alignment: .center)
        .background(.black)
        .preferredColorScheme(.dark)
}
