# MacIsland

**MacIsland** brings the **Dynamic Island experience to macOS**, inspired by iOS.
It’s a sleek, interactive floating UI that integrates system essentials like **AirDrop, temporary file storage, and battery insights**, with upcoming support for notifications and music control.

> ⚠️ **Note:** MacIsland is currently in **pre-release (experimental)**. Expect frequent updates and missing features.

---

## ✨ Features

- [x] **Drag & Drop for AirDrop** – Easily drag and drop files to share via AirDrop.
- [x] **DropTray (Temporary Storage)** – Drop files into a tray that stores them for **1 day (default)**, with customizable duration.
- [x] **Battery Status** – Instantly check your Mac’s battery percentage in the island.
- [x] **Now Playing Display** – Track title, artist, album, artwork, and remaining time, with an auto-popup chip when the track changes. _See limitations below._
- [ ] **Music Controls** – Play, pause, skip, and scrub. _(Coming Soon)_

> **Now Playing limitation.** macOS does not expose a public, system-wide "what's playing now" API to native AppKit apps — `MPMusicPlayerController` and `MusicKit.SystemMusicPlayer` are both `@available(macos, unavailable)`, and Apple's private `MediaRemote.framework` now returns "Operation not permitted" on macOS 15+. As a workaround MacIsland listens to the public `DistributedNotificationCenter` broadcasts from **Music.app** (`com.apple.iTunes.playerInfo`) and **Spotify** (`com.spotify.client.PlaybackStateChanged`). This means **browser audio (YouTube, web players), podcast apps, and any other source that doesn't post to DNC will not be detected** — we're tracking the issue and will switch back to a system-wide source the moment one is available. PRs with cleaner workarounds welcome.

---

## 🎥 Preview

![Preview](demo/preview.gif)

---

## 🚀 Installation

The **easiest way** to try MacIsland is by downloading the latest pre-built release:

👉 [Download Latest Release](https://github.com/BadRat-in/MacIsland/releases)

1. Unzip the downloaded file.
2. Drag **MacIsland.app** into your **Applications** folder.
3. Open it, and the island will appear at the top of your desktop.

---

## 🛠️ Building from Source

If you prefer to build manually:

```bash
git clone https://github.com/BadRat-in/MacIsland.git
cd MacIsland
open MacIsland.xcodeproj
```

- Select the Mac target in Xcode and hit **Run**.

---

## 📌 Usage

- **Expand / Collapse** → Click the island to toggle.
- **AirDrop** → Drag files into the island to quickly share.
- **DropTray** → Temporarily store files by dragging them onto the tray.
- **Battery Status** → Battery icon + percentage appears when charging/discharging.
- **Now Playing** → When a track is playing in Music.app or Spotify, the island briefly pops up with artwork + remaining time, and the expanded view defaults to the music panel. Tap the home icon in the music panel to access AirDrop / DropTray / Battery.
- _(Future)_ Music controls (play/pause/skip/scrub).

---

## ✅ Requirements

- **macOS**: 11.0 (Big Sur) or later
- **Xcode**: 14.0 or later (for building from source)
- **Swift**: 5.0 or later

---

## 🤝 Contribute

Want to improve MacIsland?

1. Fork this repo
2. Create a feature branch (`git checkout -b feature-branch`)
3. Commit your changes (`git commit -m "Add some feature"`)
4. Push (`git push origin feature-branch`)
5. Open a Pull Request 🎉

---

## 📄 License

Licensed under the **MPL-2.0 License**.
See [LICENSE](LICENSE) for details.

---

## 📬 Contact

Created by **Ravindra Singh**.
Questions / suggestions → [ravindra@rkinnovate.com](mailto:ravindra@rkinnovate.com)
