# Changelog

## 1.0.2 — 2026-10-18

### Fixed

- **Correct name when a connected profile is replaced.** Importing a new profile
  while connected said "VPN disconnected" with the new profile's name. It now
  names the profile that was actually disconnected.
- **Plugin folder paths with spaces or special characters work.** The path to the
  helper script is now decoded properly before it runs.

## 1.0.1 — 2026-10-18

Checked against Omarchy 4.0.5: the widget, manifest and helper are fully compatible.

### Fixed

- **Importing no longer briefly routes traffic through the VPN.** NetworkManager
  connects a profile as soon as it is imported. The import now stages the profile
  with `Table = off`, so that brief connection adds no routes, and restores normal
  routing once the profile is disconnected. A `.conf` that sets its own `Table`
  is left untouched.
- **A file chooser failure is reported.** If the file chooser can't open, you now
  get a "VPN import failed" notification instead of nothing happening. Closing the
  chooser without picking a file still does nothing.
- **IPv6 full tunnels are recognised.** A profile routing `::/0` now shows as
  "All traffic" instead of "Split tunnel".

## 1.0.0 — 2026-10-13

First release: a one-profile WireGuard toggle in the Omarchy bar, backed by
NetworkManager.
