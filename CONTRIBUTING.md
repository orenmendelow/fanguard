# Contributing

## Adding support for your Mac model

The most likely contribution is adding temperature sensor keys for Mac models I haven't tested on. If GPU temp shows N/A on your machine:

1. List all temperature keys on your Mac:
   ```bash
   # Build and run the SMC key scanner (or use a tool like smcFanControl)
   ioreg -r -c AppleSMCKeysEndpoint -l | grep -i temp
   ```
2. Find which key returns your GPU temp
3. Add it to the `gpuKeys` array in `Sources/FanGuard.swift`
4. Submit a PR with your Mac model identifier (`sysctl hw.model`)

Same applies for CPU temp keys if `Tp09` doesn't work on your model.

## Building

```bash
make build       # builds FanGuard.app and fan0-killer
make install     # copies to /Applications and launches
make clean       # removes build artifacts
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## Code structure

Everything is in `Sources/FanGuard.swift` — single-file app, no dependencies beyond system frameworks (IOKit, Cocoa, UserNotifications).

Key sections:
- **SMC** — IOKit interface for reading SMC keys (temps, fan RPM)
- **XPC Writer** — connects to the Macs Fan Control helper to write SMC keys
- **FanView** — NSView subclass for per-fan controls (segmented control + slider)
- **AppDelegate** — menu bar setup, polling loop, notifications

## Guidelines

- Keep it a single Swift file — the simplicity is a feature
- No third-party dependencies
- Test on your actual hardware before submitting fan control changes
