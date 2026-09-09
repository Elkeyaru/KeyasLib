# Changelog

All notable changes to KeyasLib are documented in this file.

## [1.2.1] - KeyasCSS resolution scaling + the XCYOS reference

### KeyasCSS

- **`KeyasCSS.parse(css, { scale = k })`** multiplies every px length in the
  sheet at load time (percentages, `auto` and colours untouched), so a
  stylesheet can be authored at 1x and rendered at any resolution. The
  consumer picks `k` from the screen size. Inline `style` on a node is not
  scaled - keep sizing in the sheet. Bitmap-font glyphs are not scaled
  either (they're a fixed atlas); register a font id per size.

### examples/xcyos_css

- The **XCYOS terminal mockup translated to KeyasCSS**: `xcyos_sheet.lua`
  (the mockup's `:root` palette + every CSS rule as a `KeyasCSS` stylesheet,
  with a header mapping each mockup feature to either "KeyasCSS" or "baked
  backdrop art") and `xcyos.lua` (the node tree + `Surface` + the rail /
  mission-list / detail-pane / profession-dock interaction, data copied
  from the mockup so the two can be diffed). This is the structural
  reference for the Last Purpose `LP_Computer` migration - see
  `MIGRATION.md` section 0.

## [1.2.0] - KeyasCSS: a CSS-style layout + paint engine

This is the release that makes "describe the UI, don't hand-place every
pixel" the primary way to build with KeyasLib. Zone-sealing and the other
helpers stay, but they're now the secondary story.

ISUI gives you filled rectangles, stretched textures and glyphs - nothing
else. **KeyasCSS** adds a box model, flexbox, rounded corners, borders,
gradients and drop shadows on top of those primitives, so a consumer mod
can hand it a tree of boxes plus a stylesheet and get it laid out and
painted in-game - matching a design instead of approximating it.

### New module: `KeyasCSS` (`common/media/lua/client/KeyasLib/KeyasCSS.lua`)

- **`KeyasCSS.parse(cssString)`** -> a stylesheet. Flat selectors (`tag`,
  `.class`, `#id`, comma lists) with normal specificity + source order.
  Shorthands expanded: `margin`, `padding`, `border`, `background`,
  `box-shadow`, `border-radius`.
- **`KeyasCSS.node{ tag, class, id, style, text, children, onClick, key }`**
  -> a node. `style` keys accept camelCase or kebab-case. `children`
  entries may be nodes or plain defs.
- **`node:resolve(stylesheet)`** merges defaults < stylesheet rules <
  inline `style`. **`node:layout(x, y, w, h)`** fills every box.
  **`node:paint(owner)`** draws it. **`node:hit(x, y)`** / **`node:find(id)`**.
- **`KeyasCSS.Surface`** (an `ISPanel`): hosts a tree, lays out and paints
  it every frame, routes clicks to the deepest node with an `onClick`.
  `:setRoot()`, `:refresh()`, `onClickMiss`.
- Supported CSS: `display: block|flex|none`, `flex-direction`, `gap`,
  `justify-content` (incl. `space-between`/`space-around`), `align-items`
  (incl. `stretch`), `flex-grow`; `width`/`height` as px / `%` / `auto`
  plus `min-`/`max-`; `margin`/`padding`; `border` (width+colour, uniform);
  `border-radius`; `background-color`; `background-image: linear-gradient(...)`;
  `box-shadow` (single); `color`; `line-height`; `text-align`; `opacity`;
  `overflow: hidden` (via `setStencilRect`). The `font` property is
  redefined to name a font registered with `KeyasUI.registerFont` (bitmap
  atlas); with none, text falls back to vanilla `UIFont`.
- Standalone draw helpers, usable without the node tree:
  `KeyasCSS.roundedRect(owner, x,y,w,h, radius, color)`,
  `KeyasCSS.dropShadow(owner, x,y,w,h, radius, {x,y,blur,color})`,
  `KeyasCSS.gradientRect(owner, x,y,w,h, "linear-gradient(...)")`,
  `KeyasCSS.color("#rrggbbaa" | "rgba(...)" | {...})`.
- **Not in v1** (documented in the file header so nobody debugs a gap):
  grid, `position: absolute/fixed`, transforms/transitions, `calc()`,
  per-corner radius, rounded corners on gradient fills, descendant/pseudo
  selectors.

### New asset + tool

- **`common/media/ui/KeyasLib/keyas_ui_9slice.png`** (128x64) - the one
  runtime asset KeyasCSS needs. Rounded corners / borders / shadows are
  9-sliced from it and tinted, so one white atlas serves every colour and
  every box size.
- **`tools/nineslice_gen/generate_nineslice.ps1`** bakes that atlas
  (System.Drawing; offline; `-Radius` / `-Blur` params). See its README.

### examples

- **`examples/css_demo/demo.lua`** - a rounded, shadowed card with a
  gradient header and a flex-column of clickable rows, built from a CSS
  string + a node tree. No Last Purpose code.

### mod.info

- `modversion` -> `1.2.0`; description rewritten to lead with KeyasCSS.

## [1.1.0] - Skin system (reproduce a designed GUI 1:1)

ISUI has no rounded corners, no gradient fill, no drop shadow and no clip
mask. That ceiling is what kept Last Purpose's "XCYOS" retro-OS terminal
looking like a rough approximation of its mockup instead of the mockup.
This release adds a way through it: bake the entire *fixed* chrome of a
window (bezel with real arc corners, radial desktop gradient, gradient
title bar, drop shadow, bevels, side rail, logo watermark, vignette +
scanlines) ONCE into a single PNG offline, blit that PNG at runtime with
`drawTextureScaled`, and only paint the *dynamic* content into named
rectangular "zones" on top of it.

### KeyasUI - skin registry

- **`KeyasUI.registerSkin(id, def)` / `KeyasUI.getSkin(id)`.** `def` carries
  `chromePath` (media path to the baked PNG), `bakeW`/`bakeH` (the size the
  PNG was authored at) and `zones` = `{ name = {x, y, w, h}, ... }` content
  rectangles in bake-space pixels. Alternatively pass `def.spec` = a table
  (typically `require`-d from a generated `zones.lua`) that itself holds
  `bakeW`/`bakeH`/`zones`. The texture is fetched lazily on first
  `getSkin`, with an error `print` (never a crash) if the path is wrong.

### KeyasUI.Window - skin mode

- **`KeyasUI.Window:new{ skin = "<id>" }`.** The window sizes itself to the
  skin's aspect ratio at ~95% of the screen and centres itself, so PZ does
  **not** pause/dim the game the way a full-screen panel does. It draws the
  chrome scaled to fill and skips its own bevel / title bar / status bar /
  auto close button (all of that is baked into the PNG). Background alpha
  is forced to 0 so only the PNG shows.
- **`window:zone("name")` -> `x, y, w, h`** in panel-local coordinates
  (the bake-space zone rect multiplied by the live scale factor).
- **`window:addZoneButton("name", onClick, opts)`** puts a transparent
  `ISButton` hit-target over a baked control (e.g. the title-bar X, a rail
  entry). `opts.hover` gives it a translucent hover tint. Buttons are
  repositioned automatically on `layout()` (resolution change, etc.).
- **`onRenderContent(x, y, w, h)`** is where the consumer paints everything
  that isn't baked - list rows, detail text, the active-rail highlight -
  using `zone()` to place it.
- Skin windows never drag (there's nothing to drag them by - the frame is
  a texture); `onMouseDown` is skin-safe.

### tools/skin_gen (offline, not shipped)

- **`generate_skin.ps1`** bakes `chrome.png` + `zones.lua` from a `.ps1`
  spec file, using .NET `System.Drawing`: `LinearGradientBrush` for the
  title/desktop gradients, `PathGradientBrush` for the vignette,
  `GraphicsPath.AddArc` for the rounded bezel corners. Windows + .NET only;
  nothing from this folder ends up in the mod.
- **`spec.xcyos.ps1`** is the worked example spec (rail labels, stripe,
  logo watermark path, window rect, title text, pane rects).
- **`README.md`** documents every spec key and how to wire the two output
  files into a consumer mod.

### examples/xcyos

- The baked `chrome.png` + `zones.lua` for the XCYOS terminal, plus
  **`demo.lua`** - a `KeyasUI.Window{ skin = "xcyos" }` with working rail
  switching and a wired baked close button, reproducing the mockup with
  KeyasLib alone (no Last Purpose code).

### mod.info

- `versionMin` `42.0` -> `42.20.4`, `modversion` -> `1.1.0`, added
  `author` and a `poster.png`.

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
