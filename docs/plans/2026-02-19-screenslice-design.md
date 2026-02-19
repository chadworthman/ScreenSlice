# ScreenSlice Design Document

## Problem

Ultrawide monitors are terrible for screen sharing. When you share the whole screen in Zoom, Google Meet, or Slack, viewers see a tiny, stretched image they can't read. Users need a way to share just a portion of their ultrawide at a standard aspect ratio.

## Solution

ScreenSlice is a macOS menu bar app that lets you define a resizable frame on your ultrawide monitor. Everything inside the frame is captured and presented as a virtual display that meeting apps can share. Everything outside the frame is dimmed so the presenter knows what's being shared.

## Architecture

Three layers working together:

### 1. Frame Overlay

A borderless, always-on-top window system on the user's ultrawide:

- **Resizable rectangle** with a visible border (subtle bright outline)
- **Draggable** via the border to reposition
- **Resize handles** on corners and edges with aspect ratio lock
- **Aspect ratio presets:** 4:3, 16:9, 16:10
- **Dimming overlay:** Semi-transparent dark layer (~30-40% opacity) covers everything outside the frame. Cosmetic only — does not block mouse clicks or interaction with underlying windows.

### 2. Capture Pipeline

- **ScreenCaptureKit** captures the rectangle defined by the frame using `sourceRect`
- Hardware-accelerated, GPU-backed CMSampleBuffers (IOSurface)
- Default 30fps, option for 60fps
- Audio capture toggle for system audio

### 3. Virtual Display Output

- **CGVirtualDisplay** (private API) creates a virtual monitor
- Created via helper subprocess (required for macOS WindowServer registration)
- Resolution matches the frame's pixel dimensions
- Updates when frame is resized or aspect ratio changes
- Meeting apps see it as a standard sharable screen named "ScreenSlice"

### Data Flow

```
Ultrawide Screen
  → [Frame defines region]
  → ScreenCaptureKit captures region (sourceRect)
  → Frames rendered to window on CGVirtualDisplay
  → Meeting app shares virtual display
```

## User Interface

### Menu Bar App

- Lives in macOS menu bar (no Dock icon — `LSUIElement` set)
- Custom app icon in /Applications

**Menu bar dropdown:**
- Start/Stop sharing
- Aspect ratio preset picker (4:3, 16:9, 16:10)
- Audio sharing toggle (on/off)
- Dimming opacity slider
- Quit

### Interaction Model

1. Launch ScreenSlice (appears in menu bar)
2. Click Start — frame overlay appears on ultrawide, virtual display is created
3. Drag/resize the frame to define the shared area
4. In meeting app, choose "Share Screen" → select "ScreenSlice" display
5. Slide application windows in and out of the frame as needed
6. Click Stop — virtual display removed, overlay disappears, screen share ends

## Technical Details

### Platform
- **Language:** Swift
- **UI Framework:** SwiftUI
- **Minimum macOS:** 15.0 (Sequoia)
- **Distribution:** Standalone .app bundle

### Key APIs
- **ScreenCaptureKit** (public, macOS 12.3+) — region capture with `sourceRect`
- **CGVirtualDisplay** (private, macOS 13+) — virtual display creation
- **CGDisplayStream** — frame delivery to virtual display
- **IOSurface** — zero-copy frame buffer sharing

### Permissions Required
- **Screen Recording** — for ScreenCaptureKit region capture
- **Accessibility** — if needed for global mouse/drag events

### Performance Targets
- 30fps default capture rate (60fps option)
- GPU-accelerated pipeline throughout
- Minimal CPU overhead

### CGVirtualDisplay Subprocess

CGVirtualDisplay requires creation in a helper subprocess for WindowServer registration. The helper:
- Creates and manages the virtual display lifecycle
- Receives configuration updates (resolution changes) via IPC
- Terminates cleanly on app quit (SIGTERM)

## Out of Scope

- Custom resolution input (presets only)
- Multi-region sharing (one frame at a time)
- Recording (live sharing only)
- Window snapping/tiling within the frame
- Virtual camera output
- Cross-platform support (macOS only)

## Risks

- **Private API (CGVirtualDisplay):** Could break in future macOS updates. Mitigation: the API has been stable across macOS 13-15, and apps like DeskPad and BetterDisplay depend on it. If it breaks, an app update would be needed.
- **Screen Recording permission:** Users must grant this. Standard macOS UX, one-time approval.

## Prior Art

- **DeskPad:** Creates a separate virtual monitor you drag windows to. Different approach — ScreenSlice captures a region of your existing screen instead.
- **BetterDisplay:** Virtual display management tool, broader scope, not focused on screen sharing UX.
