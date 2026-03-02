# Changelog

## 1.1.0 — 2026-03-02

- Per-fan controls: Auto / Manual / Off for each fan independently
- Live RPM slider in Manual mode — drag to set any speed 0–6800 RPM
- 500ms polling with `.common` run loop mode — UI updates while menu is open
- Slider initializes to current actual RPM when switching to Manual
- Overheating warning: red triangle icon + banner when both fans disabled
- macOS notification when both fans are off
- App icon (teal fan blades)

## 1.0.0 — 2026-03-02

- Initial release
- Menu bar temp display with fan icon
- Left fan auto-disabled on launch (forced to 0 RPM)
- Right fan monitoring with fault detection
- CPU/GPU temperature display with color-coded dots
- macOS notifications for fan faults and overheating
- SMC writes via Macs Fan Control XPC helper (Apple Silicon compatible)
- Standalone `fan0-killer` CLI tool
