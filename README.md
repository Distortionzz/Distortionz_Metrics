# Distortionz Metrics

> Premium developer dashboard for Qbox/FiveM — live resource browser, server health, opt-in per-script tick samples. Tier-gated via distortionz_perms.

![FiveM](https://img.shields.io/badge/FiveM-cerulean-yellow?style=flat-square&labelColor=181b20)
![Qbox](https://img.shields.io/badge/Qbox-required-red?style=flat-square&labelColor=dfb317)
![License](https://img.shields.io/badge/License-MIT-brightgreen?style=flat-square)
![Version](https://img.shields.io/github/v/release/Distortionzz/Distortionz_Metrics?style=flat-square&color=d4aa62&label=version)

---

## Overview

Three-tab developer dashboard built for the distortionz stack. Combines a live resource browser, server health time-series charts, and per-script tick sampling via an opt-in API.

## Features

### Resources tab
- Sortable table of every running resource — state pill, version, dependency count, restart count, time-since-last-start
- Allowlisted **Restart** action (admin-tier + prefix-gated to `distortionz_*`)
- Search + filter chips for started / stopped / `distortionz_` / `qbx_`

### Server tab
- Live time-series charts (last 60 samples ≈ 2 min): process memory, player count, net event throughput
- Honesty card explaining FiveM's per-resource ms-per-frame is only available via the in-game `resmon` overlay

### Ticks tab
- Local client FPS card
- Per-script tick samples for any resource that opts in via `exports.distortionz_metrics:RegisterTick(deltaMs[, label])`
- Shows avg / p95 / max / sample count / age

## Features (continued)

- **Tier-gated** — admin-only via `distortionz_perms`
- **Default keybind** F4 + `/metrics` command
- **In-NUI confirm modal + toast** (no native dialogs — they hard-hang CEF)
- **Auto-refresh** every 2s (configurable)

## Dependencies

| Resource | Required | Purpose |
|---|---|---|
| `qbx_core` | yes | Player data |
| `ox_lib` | yes | Callbacks |
| `distortionz_perms` | yes | Admin tier gating |
| `distortionz_notify` | optional | Branded notifications |

## Installation

```cfg
ensure distortionz_perms
ensure distortionz_metrics
```

## Configuration

See [`config.lua`](config.lua) for keybind, refresh interval, restart allowlist prefix, and tier requirements.

## Tick API (for other distortionz scripts)

```lua
-- In any other distortionz_* script that wants to expose tick samples
exports.distortionz_metrics:RegisterTick(deltaMs, 'optional_label')
```

## Credits

- **Author:** Distortionz
- **Framework:** [Qbox Project](https://github.com/Qbox-project)

## License

MIT — see [LICENSE](LICENSE).
