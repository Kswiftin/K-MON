# Third-party notices

## Sparkle

- **Component:** `Sparkle.framework` (embedded in the distributed app's `Contents/Frameworks`)
- **Version:** 2.9.5 (pinned exactly in `Package.swift`)
- **Author:** the Sparkle Project
- **Source:** https://github.com/sparkle-project/Sparkle
- **License:** MIT

Sparkle powers in-app updates. It ships as a signed binary framework inside the released app,
so its MIT notice travels with the release. `scripts/build-app.sh` copies the framework with
`ditto` to preserve its versioned symlinks and signed updater helpers.

## Pokémon Showdown move data

- **Component:** `Sources/PokeTokenBar/Core/ShowdownMoveOverrides.swift` (generated)
- **Source:** https://github.com/smogon/pokemon-showdown (`data/moves.ts`)
- **License:** MIT

PokéAPI is the app's move source, but its `move_meta` table stops at generation 7: most gen-8+
moves arrive with no multi-hit, drain, ailment, flinch or crit-rate at all, and it writes `0`
rather than null for a move that never misses. `scripts/extract-showdown-moves.mjs` mirrors the
corrected values from Showdown's data table and generates the Swift override map; run it again to
refresh. Only plain data values are copied — none of Showdown's engine code ships here.

## Artwork

**All artwork in this app is original.** Memory Home's mini-room sprites, wallpaper and floor
tiles are drawn as character grids in `Sources/PokeTokenBar/Core/MemoryHomePixelArtSprites.swift`
and rasterised at runtime — there are no bundled image assets and no third-party art.

This replaced a CC0 interior tileset (*4 Colour Interior Tileset* by stealthix, from OpenGameArt)
that earlier versions bundled as `oga-interior-tileset.png`. Nothing derived from that sheet
remains: the current sprites were drawn from scratch on a different palette and grid.
