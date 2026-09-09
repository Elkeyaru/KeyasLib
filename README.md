# KeyasLib

A no-content Lua library mod for Project Zomboid Build 42. Other mods
depend on it with `require=KeyasLib` in their `42/mod.info` and get:

- **KeyasCSS** - the main event: a CSS-style layout + paint engine on top
  of ISUI. Describe an interface as a tree of boxes plus a stylesheet
  (`KeyasCSS.parse`) and get a box model, flexbox, rounded corners,
  borders, gradients and drop shadows - none of which ISUI draws on its
  own - so the in-game UI matches the design instead of approximating it.
  `KeyasCSS.Surface` (an `ISPanel`) hosts a tree, lays it out every frame
  and routes clicks. Standalone helpers too: `roundedRect`, `dropShadow`,
  `gradientRect`, `color`.
- **KeyasUI** - a retro ISUI toolkit: a `Window` base class, bevel/pane
  drawing helpers, a tinted icon loader, a bitmap-font renderer that draws
  text glyph-by-glyph from a PNG atlas (B42 has no clean way to register a
  new vanilla-safe font), and a skin system that blits a pre-baked chrome
  PNG for a pixel-exact fixed window frame.

Secondary helpers (useful, but not why KeyasLib exists):

- **KeyasZones** - seal doors/windows in an area while a condition holds
  (alarms, heist sequences, story gating), with a rate-limited sweep that
  reverts damage that bypasses normal Lua actions.
- **KeyasReq** - small requirement checks (`skillAtLeast`, `flag`,
  `regionScoutedAndReturned`) that return `(boolean, reason)`, plus
  `all`/`any` combinators.
- **KeyasOptions** - a thin, double-registration-safe wrapper around
  `PZAPI.ModOptions`.

KeyasLib was extracted out of [Last Purpose](https://github.com/Elkeyaru/Last-Purpose),
a narrative mod for the Thief. See `MIGRATION.md` for how Last Purpose
moves its hand-rolled systems onto this library.

## Installing (as a consumer mod)

In your mod's `42/mod.info`:

```
require=KeyasLib
```

Then in your own Lua files, reach for the globals below - no `require()`
statements needed for KeyasLib's own files (PZ loads every `.lua` file in
every active mod automatically); just make sure your `mod.info` lists
KeyasLib as a dependency so it's actually enabled alongside you.

## A load-order rule worth repeating

PZ loads every `.lua` file independently and alphabetically; listing a mod
in `require=` does **not** force its files to load before yours. KeyasLib's
own modules follow one rule internally, and any mod consuming them should
too: **never read a KeyasLib table at file scope**. Always read it from
inside a function body, by which point every mod's files have finished
loading:

```lua
-- BAD - might run before KeyasLib.lua has loaded
local debugMode = KeyasLib.DEBUG

-- GOOD - only evaluated when this function actually runs
local function isDebug()
    return KeyasLib and KeyasLib.DEBUG
end
```

---

## KeyasLib (shared config)

```lua
KeyasLib.VERSION            -- "1.2.2"
KeyasLib.DEBUG              -- false by default
KeyasLib.debugPrint(...)    -- prints "[KeyasLib] ..." only when DEBUG is true
KeyasLib.MODDATA_PREFIX     -- "KeyasLib_" - reserved for KeyasLib's own ModData keys
KeyasLib.ZONE_MAX_REBUILDS_PER_SECOND -- 3, read by KeyasZones
```

---

## KeyasCSS

The reason KeyasLib exists. A box-model + flexbox + paint engine over ISUI.

### Quick start with `Surface`

```lua
local sheet = KeyasCSS.parse[[
  .card   { width: 380px; background: #14161d; border: 1px solid #2b2f3a;
            border-radius: 14px; box-shadow: 0 10px 30px rgba(0,0,0,0.55);
            overflow: hidden; }
  .header { height: 56px; padding: 0 16px; display: flex; align-items: center;
            justify-content: space-between;
            background: linear-gradient(180deg, #3a4a7a 0%, #26305a 100%); }
  .title  { color: #eef1ff; font: term16; }
  .body   { padding: 14px; display: flex; flex-direction: column; gap: 8px; }
  .row    { background: #1b1e27; border-radius: 10px; padding: 12px 14px;
            display: flex; justify-content: space-between; align-items: center; }
  .row.sel{ background: #2a2f6a; border: 1px solid #6f7bff; }
]]

local surface = KeyasCSS.Surface:new(x, y, w, h, {
    stylesheet = sheet,
    padding = 20,
    background = "rgba(0,0,0,0.35)",
    onClickMiss = function(s) s:removeFromUIManager() end,
    root = {
        tag = "div", class = "card", children = {
            { tag = "div", class = "header", children = {
                { tag = "div", class = "title", text = "ARCHIVO DE MISIONES" },
            }},
            { tag = "div", class = "body", children = {
                { tag = "div", class = "row", text = "Objetivo: Knox Bank",
                  onClick = function(node, s) print("clicked", node.text) end },
            }},
        },
    },
})
surface:initialise()
surface:addToUIManager()
```

`Surface` lays out and paints the tree every frame and routes a click to
the deepest node with an `onClick`. Swap the whole tree with
`surface:setRoot(newNodeOrDef)`; if you mutate node styles/text in place,
call `surface:refresh()` to re-apply the stylesheet.

### Building without `Surface`

```lua
local root = KeyasCSS.node{ tag = "div", class = "card", children = { ... } }
root:resolve(sheet)                 -- merge defaults < sheet rules < inline style
root:layout(screenX, screenY, w, h) -- fill every node.box
root:paint(self)                    -- draw (self = any ISUIElement)
local hit = root:hit(mx, my)        -- deepest node with an onClick under the point
local n   = root:find("someId")     -- depth-first by id
```

### Standalone draw helpers

No node tree needed - use these straight inside any `render()`:

```lua
KeyasCSS.roundedRect(self, x, y, w, h, radius, "#1b1e27")
KeyasCSS.dropShadow(self, x, y, w, h, radius, { x=0, y=8, blur=20, color="rgba(0,0,0,0.5)" })
KeyasCSS.gradientRect(self, x, y, w, h, "linear-gradient(180deg, #3a4a7a, #26305a)")
local c = KeyasCSS.color("#7b5cff")   -- -> {r,g,b,a} in 0..1
```

Rounded corners / borders / shadows are 9-sliced from one bundled atlas
(`media/ui/KeyasLib/keyas_ui_9slice.png`, baked by `tools/nineslice_gen`)
and tinted, so any colour and any box size works. If the atlas ever fails
to load, they degrade to plain rectangles rather than erroring.

### Supported CSS

| Area | Properties |
|---|---|
| layout | `display: block\|flex\|none`, `flex-direction`, `gap`, `justify-content` (incl. `space-between`/`space-around`), `align-items` (incl. `stretch`), `flex-grow` |
| sizing | `width`/`height` as px / `%` / `auto`; `min-`/`max-width`/`height` |
| spacing | `margin`, `padding` (+ `-top`/`-right`/`-bottom`/`-left`) |
| paint | `background-color`, `background-image: linear-gradient(...)`, `border` (width+colour, uniform), `border-radius`, `box-shadow` (single), `opacity` |
| text | `color`, `line-height`, `text-align`, `font` (**redefined**: names a font registered with `KeyasUI.registerFont`; with none, falls back to vanilla `UIFont`) |
| clipping | `overflow: hidden` (via `setStencilRect`) |

Selectors: `tag`, `.class`, `#id`, compounds (`.a.b`, `div.card`),
descendant chains (`.list .row.sel`), and comma-separated lists of those.
Specificity is the usual 100/10/1 per id/class/tag summed over the whole
selector, source order breaking ties.

**Not in v1:** grid, `position: absolute/fixed`, transforms, transitions,
`calc()`, per-corner `border-radius`, rounded corners *on* gradient fills
(gradient backgrounds paint square-cornered), child/sibling combinators
(`>` `+` `~`), pseudo-classes. `align-items: stretch` on a row whose
height is `auto` leaves children at their natural height (top-aligned).

### Rendering at any resolution

Author the sheet at 1x and let `parse` scale it:

```lua
local k = math.min(sw * 0.92 / DESIGN_W, sh * 0.92 / DESIGN_H)
local sheet = KeyasCSS.parse(css, { scale = k })   -- every px in `css` x k
```

Percentages, `auto` and colours are untouched. Inline `style` on a node is
*not* scaled - keep sizing in the sheet. Bitmap-font glyphs aren't scaled
either (fixed atlas) - register a font id per size you need.

### Examples

- `examples/css_demo/demo.lua` - a small runnable card panel.
- `examples/xcyos_css/` - the full "XCYOS terminal" mockup translated to a
  KeyasCSS stylesheet + node tree (`xcyos_sheet.lua` maps every mockup
  feature to KeyasCSS or to baked backdrop art; `xcyos.lua` builds the
  interactive tree). The reference for porting a designed HTML/CSS mockup
  onto KeyasCSS.

---

## KeyasUI

### Window

```lua
local win = KeyasUI.Window:new(100, 100, 400, 300, {
    title = "TERMINAL",
    fullscreen = false,        -- true = opaque, fills the screen, no drag/X
    showStatusBar = true,
    statusText = "READY",
    closeOnEscape = true,      -- default true
    closeOnClickOutside = true,-- default true (ignored when fullscreen)
    palette = myWarmGrayPalette, -- optional, see "Drawing helpers" below; defaults to KeyasUI.PALETTE
})
win:initialise()
win:instantiate()
win:addToUIManager()

-- Draw your own content by setting onRenderContent before/after createChildren:
function win:onRenderContent(x, y, w, h)
    KeyasUI.text(self, "> run_program.exe", x + 8, y + 8, KeyasUI.PALETTE.text)
end
```

Call `win:layout()` again after anything that could change its size (e.g.
you resize it manually) - nothing is cached across calls.

### Drawing helpers

All take the owning `ISUIElement` as the first argument:

```lua
KeyasUI.rect(self, x, y, w, h, color)          -- color = {r,g,b,a}, defaults to panel color
KeyasUI.bevel(self, x, y, w, h, raised, palette)  -- raised: true = button-out, false = sunken
KeyasUI.pane(self, x, y, w, h, color)           -- filled + sunken bevel, for content boxes
KeyasUI.titleBar(self, x, y, w, height, title, palette)
KeyasUI.statusBar(self, x, y, w, height, text, palette)
```

`bevel`/`titleBar`/`statusBar` (and `Window` via `options.palette`) take an
optional trailing `palette` table to override individual colors without
ever mutating the shared `KeyasUI.PALETTE`:

```lua
local warmGray = {
    bevelLight = {r=0.55, g=0.52, b=0.48, a=1},
    bevelDark  = {r=0.15, g=0.14, b=0.13, a=1},
    titleBar   = {r=0.30, g=0.28, b=0.26, a=1},
    text       = {r=0.90, g=0.88, b=0.85, a=1},
}
KeyasUI.bevel(self, x, y, w, h, true, warmGray)
```

Any key the override doesn't set falls back to `KeyasUI.PALETTE`'s value
for that key.

### IconSheet

```lua
local icons = KeyasUI.IconSheet.new("media/textures/KeyasLib/myicons.png")

-- whole image, tinted, scaled into a box:
icons:draw(self, x, y, 32, 32, {r=1, g=1, b=1, a=1})

-- one icon out of a multi-icon sheet:
icons:drawSub(self, 0, 0, 16, 16, x, y, 32, 32, {r=1,g=1,b=1,a=1})
```

If the PNG fails to load, both draw a bevelled placeholder box with an X
instead of erroring, so a missing asset only makes the UI plainer.

### Bitmap font

```lua
local metrics = require "MyMod/generated/terminal_16_metrics" -- see tools/font_atlas_gen
KeyasUI.registerFont("terminal16", {
    atlasPath = "media/textures/MyMod/terminal_16.png",
    metrics = metrics,
    size = 16,                  -- optional: picks a sensibly-sized vanilla fallback (see below)
    -- fallbackFont = UIFont.Medium, -- or set the fallback explicitly instead of `size`
})

KeyasUI.text(self, "HELLO", 10, 10, {r=0.5,g=0.9,b=0.5,a=1}, "terminal16")
local w, h = KeyasUI.measure("HELLO", "terminal16")
local usedHeight = KeyasUI.wrapped(self, longString, x, y, 200, color, "terminal16")
```

If `fontId` was never registered, or its atlas failed to load, every one
of these falls back to a vanilla `UIFont` automatically - text is never
simply missing. That fallback is `UIFont.Small` unless you set
`fallbackFont` (an explicit `UIFont.*`) or `size` (the pixel size the
atlas was built at - `>=27` maps to `Large`, `>=18` to `Medium`, otherwise
`Small`).

`metrics.g[codepoint]` accepts either named keys (`{x=,y=,w=,h=,xoff=,
yoff=,xadv=}`, what `tools/font_atlas_gen` produces) or a plain positional
array (`{x,y,w,h,xoff,yoff,xadv}`) - useful if you already have a metrics
table in that shape and don't want to regenerate it.

Building the atlas: see `tools/font_atlas_gen/README.md`.

---

## KeyasZones

```lua
KeyasZones.register("bank_vault", {
    bbox = {minX=1000, maxX=1010, minY=2000, maxY=2010, minZ=0, maxZ=0},
    active = function()
        return MyMod.alarmActive -- polled on every check; return a boolean
    end,
    warn = function(player) -- optional, rate-limited to once per 2s per player
        player:Say("The vault door won't budge.")
    end,
})

-- later, once the condition ends:
KeyasZones.unregister("bank_vault")

-- if you place/remove a door or window inside the bbox at runtime:
KeyasZones.rescan("bank_vault")
```

While a zone is active, `ISSmashWindow`, `ISOpenCloseDoor`,
`ISClimbThroughWindow` and `ISDestroyStuffAction` all fail validation for
targets inside the bbox, and a background sweep reverts anything broken
through some other path (direct combat, zombies) a few times a second, up
to `KeyasLib.ZONE_MAX_REBUILDS_PER_SECOND` restores per object per second.

**Known limitation:** once a window's glass is fully gone
(`isGlassRemoved()` true), it cannot be restored - design your zone so a
single window isn't the only seal point if that matters to your story.

**Before shipping:** the exact restore call
(`setSmashed`/`RecalcAllWithNeighbours`) mirrors the method names used in
Last Purpose's original `LP_BankSecurity.lua`. If your installed game
version's exact signature differs, `restoreEntry()` in `KeyasZones.lua` is
the one place to adjust it.

---

## KeyasReq

Every check returns `(boolean, humanReadableReason)`:

```lua
local ok, reason = KeyasReq.skillAtLeast(player, Perks.Lockpicking, 3)

local ok, reason = KeyasReq.flag(player, "hasVaultKey", "MyMod_") -- your own ModData prefix

KeyasReq.defineRegion("downtown", {
    cityBbox = {minX=..., maxX=..., minY=..., maxY=...},
    baseBbox = {minX=..., maxX=..., minY=..., maxY=...},
    modDataPrefix = "MyMod_",
})
-- poll periodically (e.g. from Events.OnPlayerUpdate) so the transition gets recorded:
local ok, reason = KeyasReq.regionScoutedAndReturned(player, "downtown")

-- combinators take arrays of zero-arg functions, so only what's needed runs:
local ok, reason = KeyasReq.all({
    function() return KeyasReq.skillAtLeast(player, Perks.Lockpicking, 3) end,
    function() return KeyasReq.flag(player, "hasVaultKey", "MyMod_") end,
})
local ok, reason = KeyasReq.any({ ... })
```

---

## KeyasOptions (optional)

```lua
local options = KeyasOptions.createPanel("MyMod", "My Mod", {
    addDebugTickbox = true, -- wires straight to KeyasLib.DEBUG, no restart needed
    keybind = {
        id = "MyMod_toggle", name = "Toggle terminal", defaultKey = Keyboard.KEY_F6,
        tooltip = "Opens/closes the terminal UI.",
        onChange = function(newKeyCode) MyMod.toggleKey = newKeyCode end,
    },
})
```

Safe to call more than once with the same `modOptionsID` (from your own
mod, or if something else already registered it) - you'll get the
existing panel back rather than a duplicate-registration error.

---

## Directory layout

```
42/mod.info                                  - no require=, this IS the library
common/media/lua/shared/KeyasLib/KeyasLib.lua
common/media/lua/client/KeyasLib/KeyasCSS.lua
common/media/lua/client/KeyasLib/KeyasUI.lua
common/media/lua/client/KeyasLib/KeyasZones.lua
common/media/lua/client/KeyasLib/KeyasReq.lua
common/media/lua/client/KeyasLib/KeyasOptions.lua
common/media/ui/KeyasLib/keyas_ui_9slice.png  - runtime asset for KeyasCSS rounded corners/shadows
tools/font_atlas_gen/          - offline Python tool, never packaged
tools/nineslice_gen/           - offline .NET tool, bakes the 9-slice atlas (the PNG IS packaged)
tools/skin_gen/                - offline .NET tool, bakes a full window-frame skin PNG
examples/                      - runnable KeyasCSS / skin demos, never packaged
LICENSE, README.md, CHANGELOG.md, MIGRATION.md
```

## Debugging

Flip `KeyasLib.DEBUG = true` (or use `KeyasOptions`' debug tickbox) to get
verbose `[KeyasLib] ...` logging from every module. Real errors always
print regardless of this flag.
