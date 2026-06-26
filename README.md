# GreenDeck

A private, iOS TikTok-style **green-screen recorder** that composites you over
curated background images pulled from a public Google Sheet — without ever
saving those images to your camera roll. Switch backgrounds live while
recording, capture multiple segments, and export a single vertical MP4 to Photos.

> Built from the GreenDeck build spec. **iOS-first** by design: live phone
> recording with real-time background switching using AVFoundation + Vision +
> Core Image.

---

## Status

This repository contains the **complete Swift/SwiftUI source** for the app,
structured exactly per the spec. It must be **built on macOS with Xcode** — it
cannot compile on Windows/Linux. The code was authored on Windows, so do a
clean build + device test pass before relying on it.

Requirements:
- macOS + **Xcode 15+**
- iPhone running **iOS 17+** (a physical device — the camera/Vision pipeline
  does not work in the Simulator)
- An Apple Developer signing identity (free personal team is fine for local
  installs)

---

## Opening the project

The project is defined via [XcodeGen](https://github.com/yonyz/XcodeGen) so the
`.xcodeproj` stays out of version control and is regenerated deterministically.

```bash
brew install xcodegen
cd "202606261024 - GreenDeck"
xcodegen generate
open GreenDeck.xcodeproj
```

Then in Xcode:
1. Select the **GreenDeck** target → **Signing & Capabilities** → choose your Team.
2. Pick your connected iPhone as the run destination.
3. Build & Run (⌘R).

### No XcodeGen? Manual fallback
Create a new Xcode iOS App project named `GreenDeck` (SwiftUI lifecycle, iOS 17),
delete its starter files, drag the `GreenDeck/` folder into the project, then
add these to **Info** (or Build Settings → Info.plist keys):
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- Portrait-only orientation

---

## First run

1. **Settings** → paste a **published Google Sheet CSV URL**
   (Sheet → File → Share → *Publish to web* → choose **CSV**).
   - To try it offline-ish, you can point at the bundled `sample.csv` columns —
     the included sample uses `picsum.photos` placeholder images.
2. **Sync Sheet** → downloads + caches all valid images locally.
3. **Open Deck** → browse / search / filter / star.
4. **Record** → front camera composites you over the selected background.
   Swipe or tap ◀ ▶ to switch backgrounds live (even while recording).
5. **Segments** → review, delete, reorder, then **Export & Save to Photos**.

---

## CSV schema

```csv
id,title,image_url,tags,caption,source,status,priority,notes
```

- **Required:** `id`, `image_url`
- `status` ∈ `new | used | skipped | starred | rejected`
- `priority` is an integer; higher sorts earlier
- Local workflow state (used/starred/skipped/usage counts) is **preserved**
  across re-syncs unless you choose *Reset local statuses* in Settings.

See [`GreenDeck/Resources/sample.csv`](GreenDeck/Resources/sample.csv).

---

## Architecture

```
GreenDeck/
  GreenDeckApp.swift          App entry
  AppState.swift              Central @MainActor store (data + actions)
  Models/                     BackgroundImage, RecordingSegment, AppSettings
  Services/
    SheetSyncService          fetch CSV, merge rows, cache images, report
    CSVParser                 dependency-free RFC-4180-ish parser
    ImageCacheService         download/validate/store + thumbnail/CIImage load
    PersistenceService        Codable JSON in Documents
    CameraService             AVCaptureSession → Vision → compositor → preview/record
    SegmentationService       VNGeneratePersonSegmentationRequest (mask)
    Compositor                CIBlendWithMask person-over-background, 9:16 fit
    RecordingService          AVAssetWriter (H.264 + AAC) per segment
    ExportService             AVMutableComposition → single vertical MP4
    PhotoLibraryService       save export (add-only Photos permission)
  Views/                      Home, Settings, Sync, Deck, ImageDetail,
                              Recorder (+ Metal preview), SegmentReview
  Utilities/                  Logger, FilePaths, ImageScaling, Permissions
  Resources/sample.csv
```

### Pipeline (per frame, on the capture queue)
camera `CVPixelBuffer` → Vision person mask → Core Image
`CIBlendWithMask(person, background, mask)` fitted to the 1080×1920 frame →
Metal preview **and** (if recording) `AVAssetWriter`. If segmentation returns no
mask, the compositor falls back to a picture-in-picture of the camera over the
background (spec "Mode B").

All processing is **on-device**. The only network calls are the CSV fetch and
the image downloads during sync.

---

## Mapping to the spec milestones

| Milestone | Where |
|---|---|
| 1 — Shell + sheet sync | `AppState`, `SheetSyncService`, `CSVParser`, `SettingsView`, `SyncView` |
| 2 — Cache + deck UI | `ImageCacheService`, `DeckView`, `ImageDetailView`, `CachedThumbnail` |
| 3 — Camera preview | `CameraService`, `CameraPreviewView`, `RecorderView` |
| 4 — Vision segmentation | `SegmentationService`, `Compositor` |
| 5 — Single-segment recording | `RecordingService` |
| 6 — Live switching while recording | `CameraService.setBackground` + `BackgroundChangeEvent` logging |
| 7 — Multi-segment export | `ExportService`, `PhotoLibraryService`, `SegmentReviewView` |

---

## Known tuning points (verify on device)

- **Preview orientation:** Core Image renders bottom-left origin; if the Metal
  preview appears vertically flipped on your device, flip Y in
  `MetalPreviewView.draw(_:)`. The recorded file uses the same compositor path,
  so preview and output stay consistent.
- **Performance:** if 1080×1920 segmentation drops frames, set Segmentation
  quality to **Fast** in Settings, or lower Output resolution to 720×1280. The
  spec's "segment at lower internal resolution, upscale mask" optimization is a
  natural next step inside `Compositor`.
- **Audio sync:** audio uses source presentation timestamps; the writer session
  starts on the first video frame. Confirm A/V sync on a real recording.

## Privacy
No video, image, or audio leaves the device. Networking is limited to the CSV
URL and the image URLs it references.
