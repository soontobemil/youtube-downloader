# Youtube Downloader

A native Mac app for saving YouTube videos and public Instagram Reels/video posts as MP4 or M4A audio. Built with SwiftUI, yt-dlp, FFmpeg, and Deno. No server, account, API key, or separate tool installation is required to run the bundled app. Version 0.3 added explicit 720p, 1080p, 1440p, 4K (2160p), and Best controls; source-resolution detection; a larger preview beside the download controls; and a redesigned video-and-download Dock icon. The window is resizable and follows macOS light/dark appearance.

Version 0.4 renames the app to **Youtube Downloader** and preserves the existing bundle identifier so preferences and history survive the rename. It adds Fast downloads, a faster engine launch, cached previews, transfer byte counts, and explicit Resume/Try again actions.

## Instagram support (0.5)

Paste an Instagram Reel, video post, or legacy IGTV link in the same link field. Canonical `/reel/`, `/reels/`, `/p/`, `/tv/`, and username-prefixed post links are accepted; tracking queries are removed. The preview shows Instagram's thumbnail, creator, and available source resolutions. The app name and existing YouTube preferences/history are preserved.

- Public videos accessible without sign-in are supported. No browser cookies or credentials are read. Private posts, Stories, profiles, and photo-only posts are outside this version's scope. Instagram can require sign-in or limit requests even for public posts; these failures have readable messages.
- Carousel videos save as separate files. Each completed file is added to history immediately, so partial success survives cancellation or another item's failure. The preview uses the first item; mixed photo/video posts may show a partial-failure message for photo items.
- Video uses the same quality cap and Fast downloads controls as YouTube. Resolutions are measured by pixel height, including portrait videos. Best available preserves the highest source resolution; no upscaling is performed.
- Audio prefers native M4A. When Instagram supplies combined video/audio, FFmpeg extracts AAC without re-encoding, or converts other codecs to M4A. A video without usable audio reports that clearly.
- Instagram thumbnail URLs can expire; unavailable thumbnails fall back to a placeholder. History decoding remains compatible with older versions.

## Speed improvements

- Fast downloads (enabled by default) requests up to eight concurrent chunks for native DASH/HLS downloads. Turning it off restores one chunk at a time. Direct HTTP downloads are not parallelized by this option; speeds still depend on YouTube and the connection.
- The official unpacked yt-dlp build avoids repeated self-extraction. Three local `--version` runs had median startup times of 1.933 seconds for the previous one-file build and 0.232 seconds for the unpacked build. First-launch initialization was still about two seconds. These measure engine launch, not internet transfer speed.
- A controlled local HLS fixture with injected latency completed in 4.408 seconds with one chunk and 0.885 seconds with eight, with byte-identical output and eight observed concurrent requests. This is a local verification, not a promised YouTube speed multiplier.
- Preview results are cached in memory for five minutes (up to twelve items), and unfinished preview work stops when a download starts. Progress refreshes at most four times a second.
- Interrupted downloads keep partial files. Resume download retries the same selection; changing resolution or format starts a different selection.

## Use

Open Youtube Downloader.app, paste a YouTube or Instagram link, check its preview, choose video or audio, and click Download (or press Return). Command-Shift-V uses the Paste button; ordinary Command-V also works in the link field. Change the save folder whenever needed. Open file plays a saved download; Show in Finder reveals it. Cancel stops the current download; partial files remain available for resuming. Existing completed files are preserved.

The last valid link, download preferences, and up to eight recent downloads are remembered locally. Clear list removes history entries without deleting media. Missing/moved files have disabled Open and Reveal controls. The history initially shows two recent items; View all reveals the rest. Previews load after a short typing delay and stale responses are ignored when the link changes. A preview failure does not block attempting a download. Larger previews request a high-resolution thumbnail, falling back to the standard thumbnail if unavailable.

## 4K and resolution behavior

Choose 4K to download the highest available source video at or below 2160 pixels high. A 4K source is required for a real 4K file. Lower-resolution sources are not upscaled; the source limit and expected saved resolution appear before downloading. Best has no resolution cap. The completion status and history record the actual selected resolution.

Video selection includes AVC, VP9, and AV1 streams, including WebM sources, which are merged/remuxed into MP4 without re-encoding. AVC is preferred when available at the same resolution. Some VP9/AV1 MP4 files need a compatible player such as IINA or VLC rather than QuickTime. Resolution selection is based on source pixel height, including for portrait videos.

Video filenames include their actual pixel height (for example `[1080p]` or `[2160p]`). This keeps separate-quality copies distinct, so an existing 1080p file cannot cause a new 4K download to be skipped. Files from earlier versions retain their original names; the app does not rename or remove them.

The supplied app targets Apple Silicon Macs with macOS 13 or later. It has a local ad-hoc signature and has not been notarized for public distribution.

## Build

Requires Apple's Command Line Tools (Swift compiler) and Python 3 for fetching dependencies. From this source folder:

```sh
python3 fetch-tools.py
bash build.sh
open "dist/Youtube Downloader.app"
```

All three executable downloads are pinned and SHA-256 verified. Dependency binaries live in `deps/`; the resulting app contains its own copies. To use existing dependencies or choose another output location:

```sh
bash build.sh /absolute/path/to/deps "/absolute/path/to/Youtube Downloader.app"
```

## Tests

```sh
mkdir -p .swift-cache
swiftc -swift-version 5 -module-cache-path .swift-cache Core.swift Tests.swift -o .core-tests
./.core-tests
```

Checks cover URL normalization, deceptive hosts, non-video URLs, playlist removal, argument boundaries, 4K/all-codec format selection, resolution-specific filenames, source-resolution limits, thumbnail URLs, metadata/duration parsing, history serialization, and friendly error messages. Earlier builds were exercised through the UI for MP4/M4A downloads, cancellation, previews, and history persistence. Version 0.3 was checked with a real three-second Blender sample: the resulting MP4 decoded successfully at 3840×2160, 60 fps, with AAC audio. Source-resolution detection and 4K selection were also verified in the UI.

Version 0.5 verification (November 18, 2026): URL/security and backward-compatible history checks pass. Live tests downloaded Instagram's public sample Reel and all three videos in its carousel sample. Instagram M4A export and a YouTube MP4 regression download passed. The installed app previewed and downloaded the user's Reel at 1080×1920 with HE-AAC stereo; FFmpeg decoded the complete 1:40 file successfully. A local combined-MP4 fixture also verified AAC extraction to M4A using the bundled FFmpeg with no external ffprobe. Silent-video and Instagram sign-in-required responses were exercised; they do not report success. Signature verification passed for the installed app.

## Icon

The custom red video-card icon with a dark download badge is drawn natively with AppKit. PNG and ICNS files are included in `Assets/`; `MakeIcon.swift` is the editable geometric source. To regenerate:

```sh
swiftc MakeIcon.swift -o .make-icon
./.make-icon Assets
iconutil -c icns Assets/AppIcon.iconset -o Assets/AppIcon.icns
```

## Scope and maintenance

- Individual public YouTube videos, Shorts, recorded livestreams, and Instagram Reels/video posts; active livestreams, profile feeds, Stories, and playlist-only links are excluded.
- Video downloads select the best matching video plus M4A audio when available, with other audio formats as a fallback, then merge/remux to MP4. A source with no matching format produces an error. YouTube audio-only downloads use the original M4A stream; Instagram audio can be extracted from combined MP4s.
- YouTube may restrict some videos, require sign-in, or change its download behavior. This version does not import browser cookies or handle private/age-restricted content.
- yt-dlp is pinned to 2026.10.26. Updating it requires updating the version and verified checksum in `fetch-tools.py`, rebuilding, and testing. There is no automatic updater in this version.
- Download subprocesses receive argument arrays rather than shell commands, and user yt-dlp configuration is ignored. Only normalized YouTube video URLs and Instagram post/Reel URLs are accepted by the UI.
- Files, logs, history, and preferences stay local; preview/download requests go to YouTube or Instagram and their media/thumbnail hosts. The app has no analytics.

Source files: `Core.swift` handles URLs, commands, and data types; `App.swift` manages subprocesses and app state; `Views.swift` contains the interface. Third-party details are in `THIRD-PARTY.txt` and the app's bundled `Licenses` directory.
