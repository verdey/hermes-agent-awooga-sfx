# _ops/awooga — Sound effect pack operations

Scripts for managing hermes-agent-awooga-sfx sound packs.

**Location:** Scripts live in `src/` (not `_ops/awooga/`) because they're referenced by `install.sh` and tests. The `_ops/awooga/` directory documents the convention; future projects place scripts directly in `_ops/`.

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

| Anchor | Script | Form title | `@web_safe` | `@cron_safe` |
|--------|--------|------------|-------------|-------------|
| `#play-sound` | `src/play-sound.sh` | 🔊 Play Sound | ✅ | ✅ |
| `#switch-pack` | `src/switch-pack.sh` | 🔀 Switch Pack | ✅ | ❌ |
| `#self-test` | `src/self-test.sh` | 🩺 Self-Test | ✅ | ✅ |

**Example agent instruction:**
> "The self-test came back clean — pack is active and hooks are wired. To verify in config.test: https://config.test?hermes-agent-awooga-sfx#self-test"

**Feature summary:** config.test is the single admin front door. Agents reference the exact form by anchor. No clicking around. This is how Dan wants it done.

---

## Scripts

| Script | `@anchor` | `@web_safe` | `@cron_safe` | `@timeout` | Purpose |
|--------|-----------|-------------|-------------|-----------|---------|
| `src/play-sound.sh` | `#play-sound` | ✅ | ✅ | 30s | Play an event sound (complete, approval, error, startup, tool_done) |
| `src/switch-pack.sh` | `#switch-pack` | ✅ | ❌ | 30s | Switch the active sound pack |
| `src/self-test.sh` | `#self-test` | ✅ | ✅ | 30s | Diagnose install state (event resolution, hooks, audio player) |
| `src/_lib.sh` | — | ❌ | ❌ | — | Shared: `register_hooks()`, logging. Sourced by `install.sh` and tests. |

## Convention

All scripts use `@param` headers for self-description. The cabinet (`config.test`) auto-generates forms from these headers. Args are passed **positionally** in `@param` declaration order.

## Usage via config.test

Use the deep-links in the [🧭 config.test Integration](#-config-test-integration--deep-link-convention) section above — each script has a named anchor for direct linking.

## Surface-area policy (June 2026)

This product is intentionally skinny. It plays sounds on Hermès hooks. That's it.

- **In scope:** install, register hooks, play sounds, switch packs, self-diagnose
- **Out of scope:** TUI menus, CDN pack distribution, Freesound search, custom pack builders, audio editing
- **Why:** the removed surfaces were never load-bearing; the value of a sound pack is the sounds, not the management UI

If you need a feature that used to live here (TUI, pack search, CDN install), the right answer is usually a separate small tool that *uses* awooga-sfx, not a feature added back to it.
