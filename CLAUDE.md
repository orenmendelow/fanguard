# FanGuard

macOS menu bar app for Apple Silicon MacBooks with a dead fan. Forces the broken fan off via SMC writes to stop the error beep.

## Project: `~/Documents/Code-Projects/fanguard/`

## Architecture

- **FanGuard.swift** — Single-file menu bar app. `@main` struct entry point with `-parse-as-library` compiler flag.
- **fan0-killer.swift** — Standalone CLI to force fan 0 off (legacy, replaced by FanGuard).
- **fanguard-helper.swift** — Abandoned helper daemon (macOS 26 blocks SMC even for root). Keep for reference but not used.

## macOS 26 (Tahoe) SMC Lockdown

Apple locked down SMC access in macOS 26:
- `IOServiceOpen` on `AppleSMCKeysEndpoint` / `AppleSMC` **hangs** for unsigned processes
- Returns `kIOReturnNotPermitted` (0xE00002C7) even for root
- `powermetrics --samplers smc` removed entirely
- Ad-hoc code signing with `com.apple.security.smc.readwrite` does NOT work
- Only Developer ID signed apps (like Macs Fan Control) can open SMC

## How It Works Now

- **Writes:** Route through Macs Fan Control's privileged XPC helper (`com.crystalidea.macsfancontrol.smcwrite`). MFC must be installed. Writes happen on a background `DispatchQueue` to avoid blocking UI.
- **Reads:** Not possible without Developer ID. Menu bar shows `ProcessInfo.thermalState` (OK/Fair/Hot/Crit) instead of exact temps. Fan RPM shows mode labels instead of actual RPM.
- **Override persistence:** Re-applies fan modes every 1 second to survive `thermalmonitord` resets.

## Key Technical Details

- Entry point: `@main struct FanGuardApp` calls `applicationDidFinishLaunching` explicitly (NSApplication delegate callback doesn't fire otherwise)
- Makefile uses `-parse-as-library` flag for the `@main` pattern
- SF Symbol images must be set as `isTemplate = true` for menu bar rendering
- `fan0-killer` launchd agent (`com.local.fan0-killer.plist`) was unloaded — it conflicted with FanGuard's XPC calls causing deadlocks

## Build & Install

```bash
make build    # builds app + CLI
make install  # copies to /Applications, opens
```

## Pending / Next

1. **Restore exact temp/RPM reads** — Investigate `IOHIDEventSystemClient` as alternative to SMC for thermal sensor data. Or get $99/year Apple Developer ID.
2. **Clean up abandoned helper files** — `Sources/fanguard-helper.swift` and `com.local.fanguard.helper.plist` are dead code from the failed helper approach.
3. **Update README** — Document macOS 26 compatibility and MFC dependency.
