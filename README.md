<p align="center">
  <img src="assets/icon.png" width="128" height="128" alt="SpaceMover Icon">
</p>

<h1 align="center">SpaceMover</h1>

<p align="center">
  Move macOS Spaces between displays with a click or hotkey.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

## Features

- **Move Spaces Between Displays**: Relocate any desktop or fullscreen Space to another monitor
- **Global Hotkeys**: Move the current Space left/right with `Ctrl+Option+←/→`
- **Menu Bar App**: Browse all displays and Spaces from the menu bar, with one-click moving
- **Multi-Display Aware**: Automatically detects all connected displays and their Spaces
- **Lightweight**: Runs as an accessory app with no Dock icon

## Prerequisites

SpaceMover uses Mach injection to communicate with Dock.app via private SkyLight APIs. This requires:

1. **Partial SIP Disable** — Boot into Recovery Mode and run:
   ```bash
   csrutil enable --without debug
   ```

2. **Sudoers Configuration** — On first launch, SpaceMover will prompt for administrator access to configure passwordless `sudo` for the injection loader. This only needs to happen once (or when the app is updated).

## Installation

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/twttr/SpaceMover.git
   cd SpaceMover
   ```

2. Build the payload (C dylib + loader):
   ```bash
   cd Payload && make && cd ..
   ```

3. Open in Xcode:
   ```bash
   open SpaceMover.xcodeproj
   ```

4. Build and run with `Cmd+R`

### Requirements

- macOS 13.0 or later
- Xcode 15.0 or later
- Partial SIP disable (`csrutil enable --without debug`)

## Usage

1. Click the SpaceMover icon in your menu bar
2. Displays and their Spaces are listed — hover over a Space to see the "Move to" submenu
3. Select a target display to move the Space

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+Option+←` | Move current Space to the left display |
| `Ctrl+Option+→` | Move current Space to the right display |

## Architecture

SpaceMover is a two-component system:

- **Menu bar app** (Swift) — Enumerates displays and Spaces via private SkyLight APIs, presents the UI, and handles hotkeys
- **Payload** (C dylib) — Injected into Dock.app at runtime via Mach injection (`task_for_pid`), listens on a Unix socket for space-move commands

The app and payload communicate over a Unix socket at `/tmp/com.twttr.spacemover.sock` using a versioned binary protocol.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
