# Changelog

All notable changes to KeyasLib are documented in this file.

## [1.0.1] - Correction pass before first consumer (Last Purpose)

Eight targeted fixes found while lining KeyasZones and KeyasUI up against
Last Purpose's actual `LP_BankSecurity.lua`/`LP_Computer.lua`. No module was
rewritten wholesale; `KeyasReq.lua` and `KeyasOptions.lua` are unchanged.

### KeyasZones
- **Scan every object on a square, not just `getWindow()`/`getDoor()`.**
  Those two return at most one object each and miss `IsoThumpable`
  entrances (e.g. a bank's reinforced doors/windows). `scanZoneEntries`
  now iterates `square:getObjects()` and classifies each one via
  `instanceof` (`IsoWindow`, `IsoDoor`, or an `IsoThumpable` where
  `isDoor()`/`isWindow()` is true), all under `pcall`.
- **Automatic proximity rescan.** A zone registered while its squares
  aren't loaded (player far away, or right after a save load, where the
  Lua-side entries cache is gone regardless of distance) used to stay at
  zero entries until the consumer remembered to call `rescan()`. Once a
  minute, any active zone the local player is within ~120 tiles of now
  rescans itself automatically. `KeyasZones.rescan(id)` is still there for
  a manual, immediate rescan.
- **Restore health raised from 100 to `KeyasZones.RESTORE_HEALTH`
  (100000 by default, and now a public, tunable field).** 100 let zombies
  re-break a "restored" entry within seconds, so the sweep spent its whole
  rebuild budget fighting them instead of actually holding the line.
  `unregister()` now also puts back whatever health an object had before
  KeyasZones ever touched it, instead of leaving the raised value in place
  permanently once the zone stops being enforced.

### KeyasUI
- **`bevel`/`titleBar`/`statusBar`/`Window` accept an optional trailing
  `palette` (or `options.palette` for `Window`) to override individual
  colors, without ever mutating the shared `KeyasUI.PALETTE` table.**
  `rect`/`pane` are unchanged - they already took an explicit `color`.
- **`registerFont` accepts `def.fallbackFont` (a `UIFont.*`) or `def.size`**
  (mapped `>=27 -> Large`, `>=18 -> Medium`, else `Small`), used by
  `text`/`measure` instead of a hardcoded `UIFont.Small` whenever an
  atlas hasn't loaded.
- **Glyph metrics accept a positional array (`{x,y,w,h,xoff,yoff,xadv}`)
  in addition to named keys** (`{x=,y=,w=,...}`), so an existing metrics
  file in the positional shape works without regenerating.
- **`Window:render()` self-heals if `layout()` never ran** (e.g. a
  subclass that overrides `createChildren()` without calling
  `self:layout()`), instead of erroring on nil `contentHeight`.

### mod.info
- Added `versionMin=42.0` and `modversion=1.0.1`.

## [1.0.0] - Initial release

First extraction of shared systems out of Last Purpose into a standalone
library mod, so future Keyaru mods can depend on `require=KeyasLib`
instead of copy-pasting.

### Added
- **KeyasLib** (shared config): namespace, `VERSION`, `DEBUG` flag,
  `debugPrint()`, and a couple of shared tuning constants.
- **KeyasUI**: retro ISUI toolkit.
  - `KeyasUI.Window` base class (`ISPanel` subclass) - fullscreen or
    centered, draggable title bar, close via Escape / X button / click
    outside, resolution-safe `layout()`.
  - Drawing helpers: `rect`, `bevel`, `pane`, `titleBar`, `statusBar`.
  - `KeyasUI.IconSheet` - tinted icon/sheet loader with a fallback glyph
    when a texture is missing.
  - Bitmap font renderer: `registerFont`, `text`, `measure`, `wrapped`,
    with a UTF-8 iterator and automatic fallback to vanilla `UIFont.*`.
  - `tools/font_atlas_gen`: offline Python/Pillow script that builds an
    atlas PNG + `metrics.lua` from a `.ttf`.
- **KeyasZones**: `register` / `unregister` / `rescan` for sealing doors
  and windows in a bbox while a condition holds, via a patched
  `isValid()` on `ISSmashWindow`, `ISOpenCloseDoor`, `ISClimbThroughWindow`
  and `ISDestroyStuffAction`, plus a rate-limited per-tick restoration
  sweep for damage that doesn't go through those actions.
- **KeyasReq**: `skillAtLeast`, `flag`, `regionScoutedAndReturned`,
  `all`/`any` combinators - all return `(boolean, humanReadableReason)`.
- **KeyasOptions**: thin, double-registration-safe wrapper around
  `PZAPI.ModOptions` with an optional debug tickbox and configurable
  keybind helper.
- `MIGRATION.md` describing how Last Purpose moves its hand-rolled
  systems (`LP_Computer`, `LP_BankSecurity`, `LP_Options`) onto KeyasLib.

### Known limitations
- `KeyasZones` cannot restore a window once its glass is fully removed
  (`isGlassRemoved()` true) - see `KeyasZones.lua`'s header comment.
- The exact Iso-object restore calls in `KeyasZones.restoreEntry`
  (`setSmashed`, `RecalcAllWithNeighbours`) should be checked against
  your installed game version before relying on them in a release build;
  see the call-site note at the top of `KeyasZones.lua`.
