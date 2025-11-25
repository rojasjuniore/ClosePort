# ClosePort

A lightweight macOS menu bar app to view and kill processes using TCP ports. Perfect for developers who need to quickly free up ports.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Lives in your menu bar - no dock icon
- Shows all TCP ports in LISTEN state
- Displays process name, PID, and port number
- One-click to kill any process
- Lightweight (~100KB DMG)
- Native SwiftUI app

## Screenshot

```
┌─────────────────────────┐
│ Open Ports          ↻  │
├─────────────────────────┤
│ :3000                   │
│ node (PID: 1234)    ✕   │
├─────────────────────────┤
│ :8080                   │
│ python (PID: 5678)  ✕   │
├─────────────────────────┤
│ :5432                   │
│ postgres (PID: 789) ✕   │
├─────────────────────────┤
│ 3 port(s)        Quit   │
└─────────────────────────┘
```

## Installation

### Download DMG (Recommended)

1. Download `ClosePort.dmg` from [Releases](../../releases)
2. Open the DMG file
3. Drag `ClosePort.app` to your Applications folder
4. Open ClosePort from Applications

### Build from Source

```bash
# Clone the repository
git clone https://github.com/YOUR_USERNAME/ClosePort.git
cd ClosePort

# Build with Xcode
xcodebuild -project ClosePort/ClosePort.xcodeproj -scheme ClosePort -configuration Release build

# The app will be in:
# ~/Library/Developer/Xcode/DerivedData/ClosePort-*/Build/Products/Release/ClosePort.app
```

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15+ (for building from source)

## How It Works

ClosePort uses the `lsof` command to list all TCP ports in LISTEN state:

```bash
lsof -iTCP -sTCP:LISTEN -n -P
```

When you click the X button, it sends a `kill` signal to terminate the process:

```bash
kill <PID>
```

**Note:** ClosePort can only kill processes owned by your user. System processes require administrator privileges.

## Project Structure

```
ClosePort/
├── ClosePort/
│   ├── ClosePortApp.swift      # App entry point with MenuBarExtra
│   ├── Port.swift              # Port data model
│   ├── PortService.swift       # lsof parsing and process killing
│   ├── PortListView.swift      # SwiftUI views
│   ├── Info.plist              # App configuration
│   └── Assets.xcassets/        # App icons
└── ClosePortTests/
    └── PortServiceTests.swift  # Unit tests
```

## Running Tests

```bash
xcodebuild -project ClosePort/ClosePort.xcodeproj -scheme ClosePort test
```

## Creating a DMG

```bash
# Build release version
xcodebuild -project ClosePort/ClosePort.xcodeproj -scheme ClosePort -configuration Release build

# Create DMG
mkdir -p dmg_temp
cp -R ~/Library/Developer/Xcode/DerivedData/ClosePort-*/Build/Products/Release/ClosePort.app dmg_temp/
ln -s /Applications dmg_temp/Applications
hdiutil create -volname "ClosePort" -srcfolder dmg_temp -ov -format UDZO ClosePort.dmg
rm -rf dmg_temp
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built with SwiftUI and MenuBarExtra
- Inspired by the need to quickly free up ports during development
