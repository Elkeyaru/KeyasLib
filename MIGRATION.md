# Migrating Last Purpose onto KeyasLib

KeyasLib is additive: nothing here requires Last Purpose to change its
narrative, its flows, or anything already validated in-game. The plan is
to swap one hand-rolled system at a time for the equivalent KeyasLib call,
verify nothing regressed, then move to the next. There's no requirement to
do all three at once, and no harm in leaving one of them as-is if a swap
ever looks risky close to a release.

Order of operations below is the safest one: UI first (purely visual, easy
to eyeball), then the zone-sealing security system (has real gameplay
consequences if it regresses), then options (lowest risk, do it whenever).

## 1. `LP_Computer.lua` → `KeyasUI`

`LP_Computer.lua` currently owns: the retro-OS window frame, bevel/pane
drawing, tinted icon loading with a fallback, and the glyph-by-glyph
bitmap font renderer. All four now live in `KeyasUI`.

**Do this incrementally, in this sub-order:**

1. **Drawing helpers first** - the lowest-risk swap. Anywhere
   `LP_Computer.lua` hand-draws a bevel or filled panel, replace it with
   `KeyasUI.bevel(self, ...)` / `KeyasUI.pane(self, ...)`. These are pure
   drawing calls with no state, so a visual diff (screenshot before/after)
   is enough to confirm nothing moved.
2. **Icon loading** - replace whatever loads/tints icons today with
   `KeyasUI.IconSheet.new(path)` + `:draw()` / `:drawSub()`. Keep the same
   icon PNG paths; only the loader changes.
3. **Font rendering** - this is the part worth the most care, since it's
   the most bespoke piece of `LP_Computer.lua`. Good news as of KeyasLib
   1.0.1: `LP_TermFontData.lua` can be reused **as-is**. Its glyph table
   uses positional entries (`{x, y, w, h, xoff, yoff, xadv}`), and
   `KeyasUI.text`/`measure` now read that shape directly alongside the
   named-key one - no regenerating an atlas or reshaping the metrics
   table. Just point `KeyasUI.registerFont` at the existing atlas PNG and
   `require "LastPurpose/LP_TermFontData"` for `metrics`. Then swap
   `LP_Computer`'s custom draw-glyph loop for `KeyasUI.text()` /
   `KeyasUI.wrapped()`. Compare rendered text pixel-for-pixel against the
   old renderer before calling this step done - a positioning convention
   mismatch here would only show up as slightly-off glyph placement, not
   an error. If `LP_Computer.lua` currently renders at a size vanilla fonts
   don't cover well, pass `size = <pixel size the atlas was built at>` (or
   an explicit `fallbackFont = UIFont.Large/Medium/Small`) to
   `registerFont` so the automatic fallback - if the atlas ever fails to
   load - picks a sensibly-sized vanilla font instead of always `Small`.
4. **Window frame last** - once the pieces above are proven, rebase
   `LP_Computer`'s window class onto `KeyasUI.Window` (or have it wrap one
   internally if `LP_Computer` needs to keep its own class identity for
   other reasons). Move `LP_Computer`'s current content-drawing code into
   an `onRenderContent(x, y, w, h)` callback.

Nothing about the computer's actual programs/menus/story content needs to
change in this pass - only the plumbing underneath them.

**On look and feel:** `KeyasUI.PALETTE`'s default is a phosphor-green
terminal look, which is not Last Purpose's current warm gray. Don't
reskin `LP_Computer` to match KeyasUI's default - do the opposite. Pass
Last Purpose's own colors in as `options.palette` when constructing the
`Window` (as of 1.0.1, `bevel`/`titleBar`/`statusBar`/`Window` all accept
a palette override; see `KeyasUI.lua`'s drawing-helpers header comment for
the exact keys: `bevelLight`, `bevelDark`, `titleBar`, `statusBar`, `text`,
`textDim`). This never mutates `KeyasUI.PALETTE` itself, so other
consumers (or a future second Last Purpose window with a different look)
aren't affected.

## 2. `LP_BankSecurity.lua` → `KeyasZones`

`LP_BankSecurity.lua`'s sealed-zone mechanism (wrap `isValid()` on the
relevant timed actions, run a restoration sweep) is now `KeyasZones`,
generalized to take a bbox/active-check/warn callback instead of being
hardcoded to one location. Last Purpose's own `documentacion_mod.txt`
(section 12.8) confirms the mechanism lines up closely - here's the name
crosswalk, useful while reading the two side by side:

| `LP_BankSecurity.lua` | `KeyasZones.lua` equivalent |
|---|---|
| `installBankActionGuards()` | the `isValid()` patch on `ISSmashWindow`/`ISOpenCloseDoor`/`ISClimbThroughWindow`/`ISDestroyStuffAction` |
| `LastPurposeSealGuard` (idempotency flag) | `cls._KeyasZones_patched` |
| `isProtectedBankEntrance()` | `isInsideAnyActiveZone()` |
| `shouldRemainProtected()` | your zone's `active` function |
| `restoreEntranceIfBroken()` | `restoreEntry()` |
| `LastPurposeRestoredAt` (rebuild rate limit) | `canRebuildNow()` / `KeyasZones.RESTORE_HEALTH` |
| `LastPurpose.World.BANK_PERIMETER` | your zone's `bbox` |

**Migration steps:**

1. Read off `LastPurpose.World.BANK_PERIMETER` and whatever
   `shouldRemainProtected()` currently checks (per the docs, the stage
   window `note_read` through `heist_active`, exclusive) - these become
   the `bbox` and `active` fields of a single
   `KeyasZones.register("bank_vault", {...})` call.
2. Confirm entry detection actually finds the bank's doors/windows: per
   the docs, plain combat/zombie damage on the bank's entrances doesn't go
   through a Lua action, which is exactly the case KeyasZones' entry sweep
   exists for - and if any of those entrances are built as `IsoThumpable`
   rather than a plain `IsoWindow`/`IsoDoor` (common for a purpose-built
   structure like a bank), that's exactly what 1.0.1's entry scan
   (`square:getObjects()` + `instanceof`) was added to catch, since
   `getWindow()`/`getDoor()` alone would have missed it. Register the zone
   with a temporary `active = function() return false end`, call
   `KeyasZones.rescan("bank_vault")` while standing at the bank, and check
   the debug log (`KeyasLib.DEBUG = true`) reports the expected entry
   count before wiring up the real condition.
3. Once step 2 confirms every entrance is found, flip `active` to the real
   condition and remove the old `LP_BankSecurity.lua` isValid-wrap + sweep
   code. Keep any bank-specific dialogue/warning text - just move it into
   the `warn` callback.
4. Re-test the known limitation explicitly: smash a window's glass fully
   out (`isGlassRemoved()` true) inside the zone and confirm the mod
   behaves sensibly about it not being repairable - same limitation
   `LP_BankSecurity.lua` already had, just worth re-confirming after the
   swap.
5. Drop `LastPurpose`'s own broken-glass counter logic (counted by state
   transition, not per-tick, per the docs) into the `warn` callback or
   wherever else it's read from, if that counter needs to survive the
   swap - `KeyasZones` itself has no notion of a break counter, only
   broken/not-broken.

## 3. `LP_Options.lua` → `KeyasOptions`

Lowest risk of the three. Replace `LP_Options.lua`'s direct
`PZAPI.ModOptions` calls with one `KeyasOptions.createPanel(...)` call,
carrying over the same option ids (so existing players' saved settings in
`modOptions.ini` aren't orphaned) and the same tooltips/labels. If
`LP_Options.lua` has any options beyond a debug toggle and a keybind,
those still go through the same `options` object `KeyasOptions.createPanel`
returns - it doesn't need to know about every option, only the ones it
wires up for you.

## 5. `LP_Computer.lua` chrome → `KeyasUI` skin system (1.1.0)

Section 1 above describes the *incremental* path (helpers, then icons, then
font, then the window class). KeyasLib 1.1.0 adds a second, more aggressive
option for the window-frame step specifically: instead of rebasing
`LP_Computer`'s hand-drawn frame onto `KeyasUI.Window` and still drawing
every bevel/gradient with ISUI primitives, bake the whole fixed frame to a
PNG and let `LP_Computer` only draw the parts that change.

This is the route to make the in-game window match the XCYOS mockup
pixel-for-pixel, which the primitive-drawn version can't (no rounded
corners, no real gradients, no shadow in ISUI).

**Steps:**

1. Keep `LP_Computer`'s baked-skin assets where they are for now
   (`Last Purpose/42/media/ui/LastPurpose/xcyos_chrome.png` + its zone
   rects). The `tools/skin_gen/spec.xcyos.ps1` in this repo already points
   its `logo` key at Last Purpose's `xcyos_logo.png`; re-running
   `generate_skin.ps1` regenerates both `chrome.png` and `zones.lua` from
   that one spec, so the zone rects never drift from the art.
2. In `LP_Computer.lua`, `require "KeyasLib/KeyasUI"` and, once (guarded by
   a module-level `registered` flag, inside a function - never at file
   scope), call
   `KeyasUI.registerSkin("xcyos", { chromePath = "media/ui/LastPurpose/xcyos_chrome.png", spec = require "LastPurpose/xcyos_zones" })`.
3. Change `LPComputer` so its window is a `KeyasUI.Window:derive` (or wraps
   one) constructed with `{ skin = "xcyos" }`. Delete `LP_Computer`'s own
   panel sizing / centering / `BAKE_W`/`BAKE_H` scale math - the Window
   does all of it now. `SKIN.rail`/`SKIN.detailPane`/etc. become
   `zones` in the generated `zones.lua`.
4. Move `LP_Computer`'s `paint()` body into `onRenderContent(x, y, w, h)`.
   Replace every `self:zone(bake)` call with `self:zone("<name>")`.
   Replace the hand-built `appHitboxes` loop and the transparent action
   `ISButton` with `self:addZoneButton("rail1", ...)` .. `"rail4"` and
   `addZoneButton("titleClose", ...)`.
5. The font helpers (`ensureFontsRegistered`, `text`/`measure`/`lineH`)
   already delegate to `KeyasUI.text`/`measure` - no change needed there,
   they're orthogonal to the skin system.
6. Once the skinned window renders correctly, the dead primitives in
   `LP_Computer.lua` (`bevel`, `renderRail`, `RAIL_W`, `STRIPE`,
   `TITLE_BG`, `DESKTOP`, `SCREEN`, `appGlyph`) can be deleted.

`examples/xcyos/demo.lua` in this repo is a complete, working reference for
what the migrated `LPComputer` looks like structurally.

## 4. Future unlocks → `KeyasReq`

Not a migration of existing code (Last Purpose doesn't have a
`LP_Requirements.lua` yet per the current repo layout) - just a note that
any future skill-gated or flag-gated content should reach for
`KeyasReq.skillAtLeast` / `KeyasReq.flag` / `KeyasReq.regionScoutedAndReturned`
/ `KeyasReq.all` / `KeyasReq.any` rather than hand-rolling another
one-off check, so the pattern (and its `(boolean, reason)` return shape)
stays consistent across whatever comes next.
