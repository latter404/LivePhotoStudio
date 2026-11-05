# LivePhoto Studio · 实况工坊

[简体中文](README.md) · Author: [latter404](https://github.com/latter404)

Create Live Photos and GIFs from videos on your Mac. Choose a clip on the timeline, adjust its appearance, and click **Process** to collect processed items. Then add your selection to Photos, send it with AirDrop, or export files together.

A native macOS app for Apple silicon and Intel, requiring macOS 14 or later. Using the app does not require FFmpeg, Python, Homebrew, or Xcode.

This document describes the **1.0** source tree. See the [release notes](RELEASE_NOTES.md) for availability, distributed builds, and the scope of completed validation.

## Workflow

1. **Open a video.** Before import, the left side shows a video drop area: drag a video onto it, click to choose a file, or press `⌘O`. Settings, processing controls, and actions for existing results remain on the right. With the Finder extension enabled, right-click a single video and choose **Convert to Live Photo**.
2. **Choose a clip.** The default selection is three seconds. Drag the selection to move it, its ends to change duration, and the white marker to choose the cover. Videos longer than ten seconds initially show a ten-second timeline range.
3. **Process and keep creating.** Use **Editing** for crop, rotation, watermark, and mute controls. Choose the format, quality, and custom parameters in **Output**, then click **Process**. The completed clip becomes an independent processed item. Continue with another section or another source video.
4. **Select processed items.** Click **Processed** to open the complete collection and preview, select, or remove items. When a red count badge is visible, clicking it also opens the collection. The three delivery actions always use the **selected processed items**. They do not regenerate the current editor settings when clicked.

On each launch, previously processed items remain available but start unselected. Select them in the collection when needed. Newly processed items are automatically added to the current selection, so you can create several and act on them together; existing selections are retained during the same app session.

The red badge on **Process** counts only **items created during this app session that are still available**. It is neither the historical total nor the selection count. It hides at zero and resets on relaunch; the complete history remains in **Processed**. Manually selecting historical items does not increase this badge.

| Action | Result |
| --- | --- |
| Add to Photos | Adds the selected Live Photos or GIFs to the system Photos library, with system permission. |
| AirDrop | Hands all selected items to one system AirDrop session; choose a recipient in the system window. |
| Export Files | Writes paired JPG + MOV files for Live Photos and `.gif` files for GIFs. Files are placed directly in the chosen folder, without per-item folders or overwriting existing files. |

A four-step spotlight guide appears on first use. You can skip it or reopen it from **Settings → Show Guide**.

## Features

- **Clear grouping:** Video preview and timeline on the left, separate **Editing** and **Output** groups on the right, and the **Process** action and batch controls below.
- **Timeline and cover:** Thumbnails, a draggable and resizable clip selection, a cover marker, clip playback, and range browsing for long videos.
- **Crop and rotate:** Original aspect ratio by default, freeform and common landscape/portrait ratios, draggable crop bounds, and left/right 90° rotation without added black borders.
- **Watermarks:** Custom text, size, opacity, preset positions, and free positioning by dragging. Settings are remembered; watermarking is not automatically enabled after relaunch.
- **Size and frame rate:** Original size by default, slider-based custom controls, and 4K/8K size options. Live Photo frame rates include 24, 25, 30, 50, 60 fps, and the source rate.
- **Processed collection:** Independent media for each item, preview, multiselection, batch actions, and persistence across app restarts. Later edits do not alter existing processed items.
- **Mac integration:** Simplified Chinese and English; system, light, or dark appearance; a top-level Finder context-menu action.

## Quality and formats

| Settings | Video processing |
| --- | --- |
| Original quality, with no watermark, actual crop, or custom output settings | Copies encoded video data without re-encoding when the source codec supports passthrough. |
| Only a 90° rotation | Changes orientation metadata; rotation alone does not re-encode the video or add borders. |
| Watermark, actual crop, or custom size/frame rate | Re-encodes video. The current processing path outputs SDR, converting HDR footage to standard dynamic range; this is not guaranteed lossless. |
| GIF | Original size and source frame rate by default, capped at 50 fps; at most 256 colors, with no audio. |

The Live Photo cover is generated separately as a high-quality JPEG. The encoded-video preservation statement does not mean the cover is lossless. Passthrough clips may start at an earlier keyframe and run slightly longer than the requested selection. Custom size settings do not upscale smaller footage. Video encoding requires even dimensions, which may trim the crop inward by one pixel.

4K and 8K options do not imply that every device, codec, and output mode has been tested. High-resolution encoding—and especially original-size GIF creation—can take substantial time, memory, and disk space.

## Storage and cleanup

Processed items are stored under `LivePhotoStudio/Finished` in the current user's Application Support directory by default. These are independent app-managed copies that remain available after relaunch, even if the source video moves.

The collection has no fixed item-count cap and does not evict old items based on their number. Practical capacity depends on disk space and other resources. Loading currently reads metadata item by item, so larger collections may take longer to load. The cleanup rules below are unchanged.

In **Settings → Storage & Cleanup**, you can:

- Choose separately whether to remove processed items after adding to Photos, AirDrop, or file export. **All three options are off by default.**
- Change the storage location and migrate existing items. The app verifies the copies before switching locations, then moves the old copies to Trash.

Cleanup moves only the app's processed items to the system Trash. It does not remove source videos, Photos library assets, or exported files. For Add to Photos and file export, cleanup runs only after the corresponding operation succeeds. Failed or cancelled operations keep the items.

AirDrop works differently. With its cleanup option enabled, the app asks whether the recipient received the items after the system sharing window ends. **Keep Items** is the default; cleanup occurs only if you explicitly choose **Move to Trash**. Closing the window does not prove delivery, so the question may also appear after cancelling AirDrop; choose Keep Items in that case. An explicit failure or cancellation reported by the system does not prompt or remove anything. The app never deletes processed items solely because the sharing window ended, and cannot independently confirm LIVE playback on the receiving device.

## Installation

Open the DMG attached to an official release and drag `实况工坊.app` into Applications. When updating, quit the older version before replacing it. Check the installed version in **About LivePhoto Studio**. Download the installer from [the latest release](https://github.com/latter404/LivePhotoStudio/releases/latest).

Current builds are **ad-hoc signed and have not been signed with an Apple Developer ID or notarized**. Other Macs may show a source-verification prompt. Follow macOS's own interface and your organization's device policy; no development tools are required to run the app. You may need to enable the Finder extension in System Settings before its context-menu action appears.

## Build from source

Building requires full Xcode, its macOS SDK, and Python 3. Python is used only to prepare and validate the app bundle; it is not a runtime dependency.

From the source directory:

```sh
zsh build.sh
```

The script builds `arm64` and `x86_64`, combines the universal app and Finder extension, removes absolute development-toolchain search paths, signs the result, and validates the bundle. On success, `实况工坊.app` is written to the parent of the source directory. See the [build script](build.sh), [Swift package manifest](Package.swift), and [bundle validator](validate_package.py).

For manual testing, use `zsh build.sh --test "Crop checks"`. The display name includes **Test**, the version, and the purpose. The bundle is written to `测试版本.noindex/实况工坊-测试版.app` in the parent directory. Remove it after testing. Keep only the current and previous release installers as backups; loose `.app` copies can appear as duplicate applications in macOS.

Run the automated tests with:

```sh
swift test
```

Tests use temporary directories and synthetic media. They cover pairing metadata, rotation and cropping, watermark placement, processed-item persistence, batch sharing preparation, file export, and failure cleanup. Their source is in [Tests](Tests/LivePhotoStudioTests). Passing tests do not establish installation, UI behavior, Photos library writes, or iPhone receipt on every device.

For 1.0, all 95 automated tests passed. Local UI checks covered switching from manual Light/Dark back to Follow System, live macOS appearance changes, and the installed release’s version display. See the [release notes](RELEASE_NOTES.md) for scope and limitations.

## Privacy and permissions

- Media processing stays on your Mac. The app has no built-in media-upload service, account system, or telemetry service.
- Only the **Add to Photos** and **AirDrop** actions hand selected media to the respective system service. Whether Photos syncs through iCloud is controlled by system settings.
- Processed media, titles, and clip times are stored at the selected location. If you choose a cloud-synced folder, its provider controls that folder's synchronization.
- A bounded local diagnostic log is written to `Library/Logs/LivePhotoStudio/Export.log` in the current user's home directory. It records processing phases, environment, and error information, but not media names, paths, image content, or watermark text. It is not uploaded automatically.

## Compatibility and issue reports

Preserving LIVE behavior on another device depends on the transfer path and receiving application. An AirDrop window or completion callback does not prove that the recipient saved and can play a Live Photo. Check the release notes for actual batch-transfer device validation.

A successful local run does not establish compatibility with other Apple silicon models, every Intel Mac, older macOS versions, or every iPhone. When reporting an issue, include the app version, macOS version, hardware, source resolution/frame rate, settings used, and any shareable error or crash report. Remove private paths and sensitive details first. A private original video is not required to submit an issue.

## License and credits

This project's code is distributed under the [MIT License](LICENSE), with original copyright and license notices retained for incorporated upstream code.

- [Revive](https://github.com/Ed3110/Revive): Portions of the conversion, verification, and test code are based on or adapted from this project; its [MIT copyright and license](Licenses/Revive-MIT.txt) are preserved.
- [makelive](https://github.com/RhetTbull/makelive): Reference for Live Photo sharing packages; its [MIT copyright and license](Licenses/makelive-MIT.txt) are preserved.

Detailed pinned upstream revisions and reuse scope are recorded in [Third-party notices](Licenses/THIRD_PARTY_NOTICES.txt). The project's MIT notice, third-party notices, and both complete upstream licenses are distributed with the source and app, and can be read in **About → Open-source Licenses**.

The retained Revive license includes a separate notice for the Great Vibes font; this app neither uses nor bundles that font. This project does not relicense Apple's system fonts, frameworks, SF Symbols, or product names under MIT. The app icon was created with AI assistance and its provenance is retained; those records do not themselves establish exclusive copyright or trademark rights.
