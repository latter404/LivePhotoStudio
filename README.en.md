<p align="center"><img src="Assets/AppIcon.png" width="88" alt="LivePhoto Studio icon"></p>

<h1 align="center">实况工坊 · LivePhoto Studio</h1>

<p align="center"><strong>LivePhoto Studio</strong> · Native macOS video-to-Live-Photo and GIF tool</p>

<p align="center"><a href="https://github.com/latter404/LivePhotoStudio/releases/latest">Download</a> · <a href="README.md">简体中文</a> · <a href="RELEASE_NOTES.md">Release notes</a> · <a href="https://github.com/latter404/LivePhotoStudio/issues">Report an issue</a></p>

**macOS 14+ · Apple silicon / Intel · English / Simplified Chinese · MIT licensed**

LivePhoto Studio is a native macOS app for turning video clips into Live Photos or GIFs. Processing stays on the Mac; no separate FFmpeg, Python, Homebrew, or Xcode installation is required at runtime.

## Feature screenshots

![LivePhoto Studio 1.7.1 editor with video preview, timeline, editing settings, and output settings](Assets/editor-1.7.1.png)

![LivePhoto Studio 1.7.1 output settings for Live Photos, GIFs, original size, and estimates](Assets/output-1.7.1-custom.png)

![LivePhoto Studio 1.7.1 processed list with batch selection, preview, and export](Assets/processed-1.7.1.png)

![LivePhoto Studio 1.7.1 GIF output settings](Assets/output-1.7.1-gif.png)

![LivePhoto Studio 1.7.1 Live Photo collage](Assets/collage-1.7.1.png)

## Features

- **Video to Live Photo or GIF:** Select a clip on the timeline, choose a cover, preview, and process.
- **Three-second default and custom duration:** Output defaults to at most three seconds; drag either selection edge for a custom duration.
- **Speed and GIF estimates:** Choose 0.25×, 0.5×, 1×, 1.5×, 2×, or 4×. See a sampled GIF estimate before processing and the actual size afterward.
- **Crop and rotate:** Common landscape/portrait ratios, freeform crop, and left/right 90° rotation without black borders.
- **Watermark and mute:** Text or image watermarks with size, opacity, and free positioning, plus mute.
- **Original size and custom parameters:** Keep original size by default, or adjust resolution and frame rate with 4K / 8K and 24 / 25 / 30 / 50 / 60 fps options.
- **Continuous creation and batch actions:** Click **Process** to collect clips, then add selected items to Photos, AirDrop them, export them, or make a collage.
- **Mac integration:** Drag and drop, `⌘O`, a top-level Finder context-menu action, first-use guidance, English/Chinese UI, and light/dark appearance.

## Download and install

1. Open the [latest release](https://github.com/latter404/LivePhotoStudio/releases/latest) and download the current installer.
2. Open or extract it, then drag **实况工坊.app** into **Applications**. Quit the previous version before updating.
3. The current package is ad-hoc signed and has not been Apple Developer ID signed or notarized. macOS may show a source-verification prompt on first launch.

Drop in a video, click the drop area, or press `⌘O`. Adjust editing and output settings on the right, then click **Process**. Process more clips and open **Processed** for batch actions.

| Goal | Action |
| --- | --- |
| Save to Photos | **Add to Photos** |
| Send to another device | **AirDrop** |
| Save to a folder | **Export**: paired JPG + MOV for Live Photos, `.gif` for GIFs |

Files go directly into the chosen folder, without per-item folders or overwriting existing files. Enable the Finder extension in System Settings to use the context-menu action.

## Quality and output

- When there is no actual crop, watermark, speed change, or custom output setting, encoded video data is copied without re-encoding when the source codec supports passthrough.
- Cropping, watermarking, speed changes, and custom size/frame rate re-encode video. The current processing path outputs SDR and converts HDR footage to standard dynamic range; this is not guaranteed lossless.
- A 90° rotation alone uses orientation metadata and adds no black borders.
- GIFs have at most 256 colors and no audio. Original-size high-resolution GIFs may require more time, memory, and disk space.
- A Live Photo combines a still image and a video. Keep exported JPG + MOV files together; ordinary file viewers may not display LIVE.

## Languages and appearance

| Setting | Options |
| --- | --- |
| Interface language | Follow System, Simplified Chinese, English |
| Appearance | Follow System, Light, Dark |

Change these from the **Settings** menu. A spotlight guide appears on first use and can be reopened from **Settings → Show Guide**.

## Validation scope

Validation scope is based on automated tests, build audits, and interface checks.

- Automated tests cover Live Photo pairing metadata, timing, speed, GIF estimates, crop, rotation, watermarks, batch results, file export, and failure cleanup.
- The build workflow checks the Apple silicon / Intel universal package, Finder extension, signing, resources, and runtime dependencies.
- Screenshots illustrate the interface; they are not a substitute for complete device compatibility coverage.
- 4K / 8K options describe supported output paths; time and availability depend on the source, codec, memory, and disk space.

## License and third-party notices

Author: [latter404](https://github.com/latter404). This project is distributed under the [MIT License](LICENSE).

- [Revive](https://github.com/Ed3110/Revive): portions of conversion, verification, and test code are based on or adapted from this project; its MIT copyright and license are preserved.
- [makelive](https://github.com/RhetTbull/makelive): reference for Live Photo sharing packages; its MIT copyright and license are preserved.

See [Third-party notices](Licenses/THIRD_PARTY_NOTICES.txt) for pinned references and reuse scope. Complete license texts are distributed with the source and app and can be opened from **About → Open-source Licenses**. Apple system frameworks, SF Symbols, product names, and the app icon are not relicensed under this project's MIT notice.

## Build from source

Building requires full Xcode, the macOS SDK, and Python 3. Python is used only to prepare and validate the app bundle; it is not a runtime dependency.

```sh
zsh build.sh
swift test
```

Tests use temporary directories and synthetic media. Their source is in [Tests](Tests/LivePhotoStudioTests).
