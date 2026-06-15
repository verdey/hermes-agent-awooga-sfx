# _ops/awooga — Sound effect pack operations

Scripts for managing hermes-agent-awooga-sfx sound packs.

**Location:** Scripts live in `src/` (not `_ops/awooga/`) because they're referenced by `hooks/hermes-hooks.yaml`, `Makefile`, and `install.sh`. The `_ops/awooga/` directory documents the convention; future projects place scripts directly in `_ops/`.

## Scripts

| Script | `@web_safe` | `@cron_safe` | `@timeout` | Purpose |
|--------|-------------|-------------|-----------|---------|
| `src/play-sound.sh` | ✅ | ✅ | 30s | Play an event sound (complete, approval, error, startup, tool_done) |
| `src/install-pack.sh` | ✅ | ✅ | 120s | Download and install a CDN sound pack |
| `src/search-sfx.sh` | ✅ | ✅ | 120s | Search Freesound API for sounds |
| `src/switch-pack.sh` | ✅ | ❌ | 30s | Switch the active sound pack |
| `src/admin.sh` | ❌ | ❌ | 0 | Interactive admin menu (terminal-only) |
| `src/generate-placeholders.py` | — | — | — | Python script (no @param headers) |

## Convention

All scripts use `@param` headers for self-description. The cabinet (`config.test`) auto-generates forms from these headers. Args are passed **positionally** in `@param` declaration order.

## Usage via config.test

Open `config.test` → click `hermes-agent-awooga-sfx` → each `@web_safe` script shows a form with its `@param` fields. Fill in values and click "Execute ▸".
