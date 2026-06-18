# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClosePort is a native macOS menu bar app (SwiftUI) that displays TCP ports in LISTEN state and allows one-click process termination. It uses `lsof` to discover ports and `kill` to terminate processes.

## Build & Development Commands

```bash
# Build release
xcodebuild -project ClosePort/ClosePort.xcodeproj -scheme ClosePort -configuration Release build

# Run tests
xcodebuild -project ClosePort/ClosePort.xcodeproj -scheme ClosePort test

# Create DMG for distribution
mkdir -p dmg_temp
cp -R ~/Library/Developer/Xcode/DerivedData/ClosePort-*/Build/Products/Release/ClosePort.app dmg_temp/
ln -s /Applications dmg_temp/Applications
hdiutil create -volname "ClosePort" -srcfolder dmg_temp -ov -format UDZO ClosePort.dmg
rm -rf dmg_temp
```

## Architecture

```
ClosePort/ClosePort/
├── ClosePortApp.swift   # @main entry, MenuBarExtra with network icon
├── Port.swift           # Data model (command, pid, port, address)
├── PortService.swift    # Core logic: lsof parsing + process killing
└── PortListView.swift   # SwiftUI views (PortListView, PortRow)
```

**Data flow:**
1. `PortService.fetchPorts()` runs `lsof -iTCP -sTCP:LISTEN -n -P`
2. `parseLsofOutput()` filters system apps, extracts dev ports (3000-9999, etc.)
3. `PortListView` displays ports; kill button calls `killProcess(pid:)`
4. Kill uses SIGTERM first, then SIGKILL after 100ms if process survives

**Filtering logic in PortService:**
- `excludedApps`: System processes filtered by command prefix (Spotify, rapportd, etc.)
- `devPortRanges`: Only shows ports 3000-9999, plus PostgreSQL (5432), Redis (6379), MongoDB (27017)

## Requirements

- macOS 13.0+ (Ventura)
- Xcode 15+ for building
- Swift 5.9
