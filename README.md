# FanGuard

macOS menu bar app for Apple Silicon MacBooks with a dead fan. Forces the broken fan off via SMC writes to stop the error beep, gives you full manual control over both fans, and monitors temps in real time.

Built for a 14" MacBook Pro M2 Pro with a fried left fan. Should work on any Apple Silicon MacBook with two fans.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-M1%2FM2%2FM3%2FM4-green)

## What It Does

- **Per-fan control** — each fan has a 3-way toggle: Auto / Manual / Off
- **Manual RPM slider** — set any fan to any speed (0–6800 RPM) with a live slider
- **Live RPM monitoring** — actual fan speed updates every 500ms, even while the menu is open
- **Temperature tracking** — CPU and GPU temps with color-coded status dots
- **Overheating warnings** — red alert icon in menu bar + banner in dropdown if both fans are disabled; macOS notification for critical states
- **Persistent overrides** — re-applies fan settings every 500ms to survive `thermalmonitord` resets

## Menu Bar

Shows a fan icon with CPU temp (e.g. `42°`). Click for the full control panel.

- **Normal** — fan icon, default text color
- **Hot** — orange text (CPU > 90°C)
- **Critical / No fans** — red warning triangle icon, red text

## Controls

Each fan (Left / Right) has:
- **Auto** — system manages fan speed
- **Manual** — slider appears, drag to set RPM. Initializes to current actual RPM. Live readout updates as fan responds.
- **Off** — forces fan to 0 RPM (stops error beep from dead fan)

If both fans are set to Off, a red warning banner appears in the dropdown.

## Requirements

- **macOS 13+**
- **Apple Silicon** Mac with two fans
- **[Macs Fan Control](https://crystalidea.com/macs-fan-control)** must be installed — FanGuard uses its privileged XPC helper for SMC write access (Apple Silicon requires a signed entitlement for SMC writes; MFC's helper already has it)

## Install

```bash
make install
```

Or manually:

```bash
make build
cp -R FanGuard.app /Applications/
open /Applications/FanGuard.app
```

### Add to Login Items

```bash
make login-item
```

## CLI Tool

A standalone CLI is also included for scripting:

```bash
# Force left fan off
./fan0-killer

# Restore to auto
./fan0-killer --restore
```

## How It Works

On Apple Silicon, SMC writes require the `com.apple.security.smc.readwrite` entitlement, which Apple only grants to signed apps. FanGuard works around this by connecting to the **Macs Fan Control privileged XPC helper** (`com.crystalidea.macsfancontrol.smcwrite`), which runs as root and already has SMC write access.

Every 500ms, FanGuard:
1. Reads actual RPM (`F0Ac`, `F1Ac`) and temperatures from the SMC
2. Re-applies any forced fan modes (Manual RPM or Off) to override `thermalmonitord`
3. Updates the menu bar and dropdown with live data

The timer runs in `.common` run loop mode so it continues to fire while the NSMenu is open — no stale data.

## Thermal Safety

Running on one fan is fine. Apple Silicon has hardware thermal protection — it throttles clocks before temps reach dangerous levels. The working fan stays in auto mode and ramps up to 6800 RPM as needed. Expect lower sustained performance under heavy load.

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
make uninstall
```

Or manually:

```bash
osascript -e 'tell application "System Events" to delete login item "FanGuard"'
fan0-killer --restore
rm -rf /Applications/FanGuard.app /usr/local/bin/fan0-killer
```

## License

MIT
