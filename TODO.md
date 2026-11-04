# TODO

## Replace Uptime Kuma with Gatus

`modules/aspects/features/services/uptime.nix` defines `services.uptime-kuma`, but no host includes it, so nothing runs and `uptime.nouritsu.com` doesn't resolve. Replace it with Gatus: its monitors live in Nix (`services.gatus.settings`), while Uptime Kuma's are clicked together in its web UI.

- Delete the Uptime Kuma aspect, then add `services.gatus` under the same name or a new one, with an `endpoint` (reuse subdomain `uptime` unless the user prefers `status`) and `backup.paths` for its state.
- Generate the monitored endpoints from the `endpoint` quirk pool, the same way caddy, pihole and rathole read it (see `modules/aspects/quirks.nix`). Every service declaring an endpoint is then monitored without listing it twice.
- Placement: the vps sees the homelab from outside and notices the homelab or the home line being down; the homelab can reach LAN-only endpoints. Ask the user which host or hosts to use.
- Alerts (ntfy, email, ...) are not decided. Ask before adding any.
- Style: house den idioms, commit as `feat: ...`, no scopes. Deploys go through `nix develop -c deploy <host>`; let the user run them.

Related: the desktops already have `isup` (`~/.config/nixos`, `packages/isup`), a local on-demand checker. Once Gatus is up, `isup` could also show Gatus's history via `/api/v1/endpoints/statuses`. That change belongs in the desktop repo, not here.
