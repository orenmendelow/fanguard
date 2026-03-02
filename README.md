# FanGuard

macOS menu bar app for Apple Silicon MacBooks with a dead fan. Forces the broken fan off via SMC writes to stop the error beep, monitors the remaining fan and CPU/GPU temps, and alerts you if anything goes wrong.

Built for a 14" MacBook Pro M2 Pro with a fried left fan. Should work on any Apple Silicon MacBook with two fans.

![menu bar](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)

## What It Does

- **Disables the dead fan** — forces it to manual mode with 0 RPM target so the SMC stops trying to spin it (and stops beeping)
- **Monitors the working fan** — shows RPM in the menu bar, alerts if it fails
- **Tracks temperatures** — CPU and GPU temps with color coding (green → orange → red)
- **Sends notifications** — macOS alerts if the remaining fan stops or temps go critical
- **Re-applies every 3 seconds** — survives `thermalmonitord` overrides

## Menu Bar

Shows `45° R:2500` format — CPU temp and right fan RPM. Click for details:

- Left/right fan status with RPM
- CPU and GPU temperatures
- Thermal status (Cool / Warm / Hot / OVERHEATING)
- Toggle to enable/disable the dead fan override

Color coding:
- **Default** — everything normal
- **Orange** — CPU > 90°C, throttling likely
- **Red** — CPU > 100°C or right fan failure

## Requirements

- **macOS 13+** (uses `MenuBarExtra`-era APIs)
- **Apple Silicon** Mac with two fans
- **[Macs Fan Control](https://crystalidea.com/macs-fan-control)** must be installed — FanGuard uses its privileged helper for SMC write access (Apple Silicon requires a signed entitlement for SMC writes; MFC's helper already has it)

## Install

### From Source

```bash
# Build
swiftc -o FanGuard Sources/FanGuard.swift -framework IOKit -framework Cocoa -framework UserNotifications -O

# Create app bundle
mkdir -p FanGuard.app/Contents/MacOS
cp FanGuard FanGuard.app/Contents/MacOS/
cp Info.plist FanGuard.app/Contents/

# Install
cp -R FanGuard.app /Applications/
open /Applications/FanGuard.app
```

### Add to Login Items

```bash
osascript -e 'tell application "System Events" to make login item at end with properties {path:"/Applications/FanGuard.app", hidden:true}'
```

## CLI Tool

A standalone CLI is also included for scripting:

```bash
# Build
swiftc -o fan0-killer Sources/fan0-killer.swift

# Force left fan off
./fan0-killer

# Restore to auto
./fan0-killer --restore
```

## How It Works

On Apple Silicon, SMC writes require the `com.apple.security.smc.readwrite` entitlement, which Apple only grants to signed apps. FanGuard works around this by connecting to the **Macs Fan Control privileged XPC helper** (`com.crystalidea.macsfancontrol.smcwrite`), which runs as root and already has SMC write access.

Every 3 seconds, FanGuard:
1. Reads `F0Ac`, `F1Ac` (actual RPM), `F0Tg`, `F1Tg` (target RPM), temps
2. Writes `F0Md=01` (forced mode) and `F0Tg=00000000` (0 RPM target) for the dead fan
3. Updates the menu bar display
4. Checks if the working fan is healthy (actual > 0 when target > 0)

The dead fan reads 0 RPM, which matches the 0 RPM target → SMC sees no fault → no beep.

## Thermal Safety

Running on one fan is fine. Apple Silicon has hardware thermal protection — it will throttle clocks before temps reach dangerous levels. The working fan stays in auto mode and ramps up to 6800 RPM as needed. Expect lower sustained performance under heavy load.

## SMC Keys Reference

| Key | Type | Description |
|-----|------|-------------|
| `FNum` | ui8 | Number of fans (2) |
| `F0Ac` | flt | Fan 0 actual RPM |
| `F0Tg` | flt | Fan 0 target RPM |
| `F0Md` | ui8 | Fan 0 mode (0=auto, 1=forced) |
| `F0Mn` | flt | Fan 0 minimum RPM |
| `F0Mx` | flt | Fan 0 maximum RPM |
| `F1Ac`–`F1Mx` | | Same for Fan 1 |
| `Tp09` | flt | CPU proximity temperature |

## Uninstall

```bash
# Remove login item
osascript -e 'tell application "System Events" to delete login item "FanGuard"'

# Restore fan to auto
/Applications/FanGuard.app/Contents/MacOS/FanGuard --restore 2>/dev/null
# or if you have the CLI:
fan0-killer --restore

# Delete
rm -rf /Applications/FanGuard.app
rm -f /usr/local/bin/fan0-killer
```

## License

MIT
