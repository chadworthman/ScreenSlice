# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
swift build                    # Debug build
swift build -c release         # Release build
./scripts/build-app.sh         # Release build + .app bundle + codesign
```

The build script outputs to `.build/release/ScreenSlice.app`. No test suite exists; testing is manual (launch app, verify sharing lifecycle, test in Zoom/Meet).

## Architecture

ScreenSlice is a macOS menu bar app (~985 lines of Swift) that captures a user-selected screen region and presents it as a virtual display for screen sharing. It uses Swift Package Manager with two targets:

- **CGVirtualDisplayPrivate** — C target bridging Apple's private `CGVirtualDisplay` API via an Objective-C header
- **ScreenSlice** — The executable, depending on the above

### Data Flow

```
MenuBar (start) → AppDelegate orchestrates →
  1. OverlayWindow appears (dimming + resizable frame)
  2. VirtualDisplayManager creates CGVirtualDisplay (resolution matches aspect ratio)
  3. ScreenCaptureManager starts SCStream for the frame region
  4. Captured IOSurface frames → VirtualDisplayManager renders to window on virtual display
  5. Meeting app shares the "ScreenSlice" display
```

### Key Source Files (all under `ScreenSlice/Sources/`)

| File | Role |
|------|------|
| `AppDelegate.swift` | Orchestrator — wires all managers together, owns sharing lifecycle |
| `MenuBarController.swift` | NSStatusItem menu with start/stop, aspect ratio presets (landscape + portrait), audio toggle, dim slider, GitHub link |
| `VirtualDisplayManager.swift` | Creates CGVirtualDisplay, renders IOSurface frames to a window on it |
| `ScreenCaptureManager.swift` | SCStream setup, coordinate conversion (NSScreen↔CoreGraphics), capture rect updates |
| `OverlayWindow.swift` | Borderless always-on-top transparent window |
| `OverlayContentView.swift` | Even-odd fill dimming, 8 resize handles, top + bottom drag bars, aspect ratio enforcement |

### Critical Patterns

- **Coordinate systems**: NSScreen uses bottom-left origin; CoreGraphics uses top-left. `ScreenCaptureManager` handles the conversion — get this wrong and capture rects are mispositioned.
- **Split callbacks**: `onRegionChanged` fires during drag (lightweight — updates capture rect only). Expensive operations like virtual display recreation should only happen on mouse-up to avoid jank.
- **Callback-based wiring**: Managers communicate via closures (`onFrameReceived`, `onRegionChanged`, `onRegionFinished`, `onStartStop`) set up in `AppDelegate.applicationDidFinishLaunching`. No delegates or Combine.
- **`@MainActor` + `@unchecked Sendable`**: All manager classes are `@MainActor`. Cross-actor closure passing uses `@unchecked Sendable`.
- **Virtual display timing**: 1-second delay after creating CGVirtualDisplay before creating the render window, so macOS WindowServer registers the display first.

## Platform & Frameworks

- **macOS 15.0+ (Sequoia)**, Swift 6.0
- **ScreenCaptureKit** for hardware-accelerated region capture
- **CGVirtualDisplay** (private API) for virtual display — may break in future macOS versions
- **IOSurface** for zero-copy frame delivery
- **AppKit** for UI (not SwiftUI, despite SwiftUI app entry point)

## Conventions

- Logging: `ssLog()` writes to both `NSLog` and `~/ScreenSlice.log` (cleared on launch)
- App runs as `.accessory` activation policy (menu bar only, no Dock icon)
- Virtual display resolution matches capture aspect ratio (e.g. 4:3 → 1440×1080, 16:9 → 1920×1080, 3:4 → 1080×1440)
- Ad-hoc codesigning only (no Developer ID) — TCC permissions reset on rebuild
