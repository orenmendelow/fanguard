# Troubleshooting

## "FanGuard doesn't appear in the menu bar"

FanGuard is a menu-bar-only app (no Dock icon). Look for a small fan icon with a temperature number near your other menu bar icons. If you have many menu bar items, macOS may hide it behind the notch — try closing other menu bar apps.

To relaunch: `open /Applications/FanGuard.app`

## "Fan writes fail" / fans don't respond to Manual or Off

FanGuard requires **Macs Fan Control** to be installed. It uses MFC's privileged helper (`com.crystalidea.macsfancontrol.smcwrite`) for SMC write access on Apple Silicon.

**Check the helper is running:**

```bash
ps aux | grep macsfancontrol.smcwrite
```

You should see a root process. If not:

1. Open Macs Fan Control at least once (it installs the helper on first launch)
2. If it still doesn't appear, reinstall Macs Fan Control

**Note:** Macs Fan Control does not need to be running — only its helper daemon needs to be installed. The helper persists as a LaunchDaemon after installation.

## "SMC reads fail" / temps show N/A

FanGuard reads SMC sensors directly via IOKit. This requires no special permissions on macOS 13+, but can fail if:

- Another app has an exclusive lock on the SMC (unlikely but possible)
- The IOKit `AppleSMCKeysEndpoint` service isn't available (would indicate a system issue)

Try reading manually:

```bash
# Build the debug reader
cd /path/to/fanguard
swiftc -o /tmp/smc_debug Sources/FanGuard.swift -framework IOKit -framework Cocoa -framework UserNotifications
# Or use the simpler test:
ioreg -r -c AppleSMCKeysEndpoint -l | head -20
```

## "Temps show but GPU always says N/A"

FanGuard tries several temperature keys (`Tg0f`, `Tg0T`, `TG0P`, `Tg05`). Your Mac model may use a different key. File an issue with your Mac model and we can add the correct key.

## "Fan RPM doesn't update while menu is open"

This was a known issue in v1 (timer didn't fire during NSMenu tracking). Fixed in the current version — the timer runs in `.common` run loop mode. Make sure you're on the latest build:

```bash
cd /path/to/fanguard
git pull && make install
```

## "Both fans show 0 RPM / Idle in Auto mode"

This is normal when the system is cool. Apple Silicon Macs turn fans completely off at low temps. Run a heavy workload (compile something, export video) and the right fan should spin up.

## "The beeping came back"

FanGuard re-applies the fan override every 500ms. If the beeping returned:

1. Check FanGuard is running: look for the fan icon in the menu bar
2. Check the left fan is set to "Off" in the dropdown
3. If FanGuard crashed, relaunch it: `open /Applications/FanGuard.app`

If beeping occurs during boot (before FanGuard launches), that's the firmware — FanGuard can't suppress pre-boot beeps. The only fix for boot beeps is replacing the fan or the tachometer resistor trick (see below).

## Hardware alternatives

If software control isn't sufficient:

- **Replace the fan** — left fan parts are ~$20-35 on iFixit/Amazon, 20 min swap with a Torx screwdriver
- **Tachometer resistor trick** — solder a 1kΩ–4.7kΩ pull-up resistor on the tachometer pin of the fan connector to simulate a spinning fan signal to the SMC. Stops beeping at the hardware level. Any Mac repair shop can do this.

## Compatibility

Tested on:
- MacBook Pro 14" M2 Pro (Mac14,9) — macOS Sequoia

Should work on any Apple Silicon MacBook with two fans (M1 Pro/Max, M2 Pro/Max, M3 Pro/Max, M4 Pro/Max). The SMC key scheme (`F0Ac`, `F1Ac`, etc.) is consistent across these models.

**Will NOT work on:**
- Intel Macs (different SMC interface — use `smcFanControl` instead)
- MacBook Air (single fan or fanless)
- Mac Mini / Mac Studio / Mac Pro (different fan topology)
