# PikoChan Notch MVP Design

## Overview
PikoChan is a macOS AI assistant that lives inside the hardware notch. The MVP focuses on a buttery-smooth, native-feeling UI with no backend.

## Architecture

### File Structure
```
PikoChan/
├── PikoChanApp.swift               — Entry point + AppDelegate
├── Core/
│   ├── NotchState.swift             — 4-state enum
│   └── NotchManager.swift           — Panel lifecycle, mouse monitoring, state machine
├── Views/
│   ├── NotchContentView.swift       — Root view: state-driven layout
│   ├── ExpandedView.swift           — Sprite + text/voice buttons
│   ├── TypingView.swift             — Capsule text field with focus
│   └── NotchShape.swift             — Animatable notch shape mask
├── Utilities/
│   ├── PikoPanel.swift              — NSPanel subclass (borderless, transparent)
│   ├── NSScreen+Notch.swift         — Notch detection via auxiliaryTopLeftArea/Right
│   └── VisualEffectView.swift       — NSVisualEffectView SwiftUI wrapper
└── Assets.xcassets/
    └── pikochan_sprite.imageset/
```

### Key Decisions
- **Inline implementation** (not DynamicNotchKit dependency) for full control over 4-state system
- **PBXFileSystemSynchronizedRootGroup** — Xcode auto-discovers files, no pbxproj edits needed
- **@Observable** NotchManager (not ObservableObject) for modern observation
- **Sandbox disabled** — notch overlay needs unrestricted window management
- **LSUIElement = YES** — no dock icon, agent app

### Window Management (from DynamicNotchKit patterns)
- `PikoPanel` subclass of `NSPanel` with `.borderless`, `.nonactivatingPanel`
- Level `.statusBar` (above apps, below system dialogs)
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]`
- Panel covers top center of screen (400pt wide x 420pt tall)
- Transparent background — mouse events pass through transparent areas

### Notch Detection
- `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` to detect hardware notch
- Fallback for non-notch displays: 220pt wide centered at menu bar height

### State Machine
| State | Visual | Mouse Events |
|-------|--------|--------------|
| hidden | Invisible behind notch + 0.001-opacity hover trigger | `ignoresMouseEvents = true` (global monitor handles hover) |
| hovered | 12px peek below notch, black fill | `ignoresMouseEvents = false` |
| expanded | 320x280 panel, `.hudWindow` material, sprite + buttons | `ignoresMouseEvents = false` |
| typing | 320x260, smaller sprite + capsule TextField | `ignoresMouseEvents = false` |

### Transitions
| From → To | Animation |
|-----------|-----------|
| hidden → hovered | `.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2)` |
| hovered → hidden | `.smooth(duration: 0.3)` |
| hovered → expanded | `.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.2)` |
| expanded → typing | `.snappy(duration: 0.35)` |
| expanded/typing → hidden | `.smooth(duration: 0.3)` |

### Mouse Handling
- **Global monitor** (`NSEvent.addGlobalMonitorForEvents`): detects cursor in notch zone when app isn't frontmost
- **Local monitor**: same for when panel has focus
- **Key monitor**: Escape key to dismiss
- **`.onHover`** on SwiftUI content: manages hovered/collapse states
- **Collapse timer**: 400ms delay on mouse exit from expanded/typing states

### Sprite
- `pikochan_demo.png` with `.interpolation(.none)` for pixel-art crispness
- 140pt in expanded state, 80pt in typing state
