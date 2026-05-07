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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nowPlayingManager.title ?? "")
                            .font(.system(.headline, design: .rounded))
                            .lineLimit(1)
                        if let artist = nowPlayingManager.artist, !artist.isEmpty {
                            Text(artist)
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let album = nowPlayingManager.album, !album.isEmpty {
                            Text(album)
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    homeButton
                }
                Spacer(minLength: 0)
                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
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

    private var artwork: some View {
        Group {
            if let image = nowPlayingManager.artwork {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Rectangle().foregroundStyle(.white.opacity(0.08))
                    Image(systemName: "music.note")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
