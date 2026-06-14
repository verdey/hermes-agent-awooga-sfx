# Sound Attributions

All sounds in the bundled packs of **hermes-agent-awooga-sfx** are synthesized
in code using Python's `wave` and `math` modules from the standard library.
No third-party audio samples, recordings, or sound files are used.

## Bundled Packs

| Pack | Source | License |
|------|--------|---------|
| `awooga-tugboat` | Synthesized (frequency sweeps + sustained tones) | MIT |
| `ricola-horn` | Synthesized (multi-harmonic alpine horn synthesis) | MIT |
| `submarine-dive` | Synthesized (low-frequency dive horn synthesis) | MIT |
| `8bit-blip` | Synthesized (square/pulse wave 8-bit synthesis) | MIT |

## CDN / Community Packs

Community packs downloaded via `install-pack.sh` may contain sounds from
various sources. Each pack's `ATTRIBUTIONS.md` file (inside the pack directory)
contains the specific license and attribution information for that pack.

## Freesound Packs

Packs created via `search-sfx.sh` download sounds from the [Freesound](https://freesound.org)
API. Individual sound licenses vary (CC0, CC-BY, CC-BY-NC, etc.). Check each
sound's page on Freesound for the specific license terms. The `search-sfx.sh`
script automatically generates an `ATTRIBUTIONS.md` in each custom pack directory.

## License

This project (hermes-agent-awooga-sfx) is released under the MIT License.
The synthesized sounds in the bundled packs are also MIT-licensed.
Third-party sounds downloaded from CDN packs or Freesound are subject to
their respective licenses as documented in each pack's `ATTRIBUTIONS.md`.