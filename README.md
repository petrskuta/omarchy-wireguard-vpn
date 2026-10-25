# WireGuard VPN

A single WireGuard profile in the Omarchy bar, run by NetworkManager.
It doesn't need `wg-tools` or sudo.

- **Left click** opens the panel: on/off switch, server, address, DNS, routing, traffic.
- **Right click** connects or disconnects.
- **Panel keys:** `enter`/`t` toggle, `i` import, `r` refresh, `esc` close.
- **Notifications** appear on connect, disconnect, and errors, including changes made outside the widget, for example with `nmcli`.

## Profile

Use **Import profile** in the panel and pick a wg-quick `.conf` file, or run:

```bash
~/.config/omarchy/plugins/petrskuta.wireguard/bin/wireguard-vpn import ~/path/to/work.conf
```

The profile is stored by NetworkManager in `/etc/NetworkManager/system-connections/`
(root-only), with autoconnect off. Importing again replaces the old profile.
NetworkManager ignores `PreUp`/`PostUp`/`PreDown`/`PostDown` lines.

## CLI

`bin/wireguard-vpn status | up | down | toggle | import [file] | remove`

## Install

```bash
omarchy plugin add https://github.com/petrskuta/omarchy-wireguard-vpn.git --enable
```
