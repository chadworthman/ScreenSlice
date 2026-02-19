# ScreenSlice

A macOS menu bar app that captures a resizable region of your ultrawide monitor and presents it as a virtual display for screen sharing.

## Why

Ultrawide monitors are great for productivity, but screen sharing the entire display in Zoom or Google Meet gives viewers a tiny, unreadable window. ScreenSlice lets you select just the region you want to share, and meeting apps see it as a separate display at a normal aspect ratio.

## How It Works

1. ScreenSlice creates a virtual display (1920x1080) using the CGVirtualDisplay private API
2. A dimming overlay appears on your screen with a resizable frame showing the shared region
3. ScreenCaptureKit captures the frame region and renders it to the virtual display
4. In your meeting app, share the "ScreenSlice" display instead of your ultrawide

## Requirements

- macOS 15 (Sequoia) or later
- Screen Recording permission

## Build

```bash
./scripts/build-app.sh
```

This builds a release binary, packages it as `ScreenSlice.app`, and codesigns it.

## Install

```bash
cp -r .build/release/ScreenSlice.app /Applications/
```

## Usage

1. Launch ScreenSlice -- a `rectangle.dashed` icon appears in the menu bar
2. Click **Start Sharing** -- a dimming overlay appears with a 4:3 frame
3. **Move** the frame using the drag handle (white pill at the top)
4. **Resize** using the corner and edge handles
5. Open your meeting app and share the **ScreenSlice** display
6. Use the menu bar to change aspect ratio (4:3, 16:9, 16:10) or toggle audio
7. Click **Stop Sharing** when done

## Permissions

ScreenSlice requires **Screen Recording** permission. On first launch, macOS will prompt you. If capture fails:

1. Open System Settings > Privacy & Security > Screen Recording
2. Enable ScreenSlice
3. Quit and relaunch the app

Use **Check Permissions** in the menu bar to verify access.

## Tech Stack

- Swift 6, SwiftUI, AppKit
- ScreenCaptureKit (region capture)
- CGVirtualDisplay (private API, virtual display creation)
- IOSurface (frame rendering)

## Limitations

- CGVirtualDisplay is a private API and may break in future macOS updates
- The virtual display is fixed at 1920x1080 regardless of capture region size
- No code signing with a Developer ID -- TCC permissions may reset on rebuild
