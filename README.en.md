<p align="center"><img src="Assets/AppIcon.png" width="88" alt="LivePhoto Studio icon"></p>

<h1 align="center">LivePhoto Studio · 实况工坊</h1>

<p align="center"><a href="https://github.com/latter404/LivePhotoStudio/releases/tag/v1.0">Download</a> · <a href="README.md">简体中文</a> · <a href="RELEASE_NOTES.md">Release notes</a></p>

**macOS 14+ · Apple silicon / Intel · English / Simplified Chinese · MIT licensed**

LivePhoto Studio is a native macOS app for turning video clips into Live Photos or GIFs with local processing.

## Implemented

- Drag-and-drop import, timeline selection, and cover selection
- Live Photo and GIF output
- Aspect-ratio/freeform crop, left/right 90° rotation, and watermarks
- Original-size preference and custom output parameters
- Photos, AirDrop, and paired JPG + MOV export
- Finder context-menu entry, Simplified Chinese/English, light/dark appearance, and first-use guidance

## Download and install

Download [LivePhotoStudio-1.0-universal.dmg](https://github.com/latter404/LivePhotoStudio/releases/download/v1.0/LivePhotoStudio-1.0-universal.dmg), open it, and drag the app into Applications. The source archive and `SHA256SUMS.txt` are also provided.

The package supports macOS 14+, Apple silicon, and Intel. It is ad-hoc signed and not notarized.

## Validation scope

Automated tests cover Live Photo pairing, timing, crop, rotation, watermarks, output files, and failure cleanup. The build workflow checks the universal package, Finder extension, resources, and signing status. Public validation uses synthetic media and local build checks.

## License

Author: [latter404](https://github.com/latter404). The project uses the MIT License; third-party licenses are in [Licenses](Licenses).
