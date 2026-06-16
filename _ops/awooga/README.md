# _ops/awooga — Sound effect pack operations

Scripts for managing hermes-agent-awooga-sfx sound packs.

**Location:** Scripts live in `src/` (not `_ops/awooga/`) because they're referenced by `hooks/hermes-hooks.yaml`, `Makefile`, and `install.sh`. The `_ops/awooga/` directory documents the convention; future projects place scripts directly in `_ops/`.

---

## 🧭 config.test Integration & Deep-Link Convention

Dan interacts with this product exclusively through **[config.test](https://config.test)** — the admin front door. **Agents MUST deeplink Dan to the exact config section rather than describing where to click.** This is an explicit operational instruction: when this product is involved, go to config.test and anchor the link to the specific script/form.

### How config.test works with this product

config.test auto-discovers scripts across `~/code` and `~/pipelines`. Every `@web_safe` script gains a form driven by its `@param` headers. Args are passed **positionally** in `@param` declaration order.

**Deep-link pattern:**
```
https://config.test?<script-name>#<anchor>
```
The hash/anchor maps directly to the `@anchor` value on each script's `@param` line.

### Anchors → config.test forms

| Anchor | Script | Form title | @web_safe | @cron_safe |
|--------|--------|-------------|-----------|------------|
| `#play-sound` | `src/play-sound.sh` | 🔊 Play Sound | ✅ | ✅ |
| `#install-pack` | `src/install-pack.sh` | 📥 Install Pack | ✅ | ✅ |
| `#search-sfx` | `src/search-sfx.sh` | 🔍 Search SFX | ✅ | ✅ |
| `#switch-pack` | `src/switch-pack.sh` | 🔀 Switch Pack | ✅ | ❌ |
| `#admin` | `src/admin.sh` | Admin Menu | ❌ | ❌ |

**Example agent instruction:**
> "I surfaced the diagnostic output — the issue is the Hermes hooks aren't registered. Go to config.test and run `#install-hooks` if that form exists, or manually re-run install.sh. Here's the deep link: https://config.test?hermes-agent-awooga-sfx#play-sound"

**Feature summary:** config.test is the single admin front door. Agents reference the exact form by anchor. No clicking around. This is how Dan wants it done.

---

## Scripts

| Script | `@anchor` | `@web_safe` | `@cron_safe` | `@timeout` | Purpose |
|--------|-----------|-------------|-------------|-----------|---------|
| `src/play-sound.sh` | `#play-sound` | ✅ | ✅ | 30s | Play an event sound (complete, approval, error, startup, tool_done) |
| `src/install-pack.sh` | `#install-pack` | ✅ | ✅ | 120s | Download and install a CDN sound pack |
| `src/search-sfx.sh` | `#search-sfx` | ✅ | ✅ | 120s | Search Freesound API for sounds |
| `src/switch-pack.sh` | `#switch-pack` | ✅ | ❌ | 30s | Switch the active sound pack |
| `src/admin.sh` | `#admin` | ❌ | ❌ | 0 | Interactive admin menu (terminal-only) |
| `src/_lib.sh` | — | ❌ | ❌ | — | Shared: `register_hooks()`, logging helpers. Sourced by `install.sh` and tests. |

## Convention

All scripts use `@param` headers for self-description. The cabinet (`config.test`) auto-generates forms from these headers. Args are passed **positionally** in `@param` declaration order.

## Usage via config.test

Use the deep-links in the [🧭 config.test Integration](#-config-test-integration--deep-link-convention) section above — each script has a named anchor for direct linking.
