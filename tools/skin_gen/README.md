# skin_gen

Bakes a **KeyasUI skin**: one `chrome.png` (the whole fixed window frame -
CRT bezel with rounded corners, desktop gradient, gradient title bar,
bevels, drop shadow, side rail, logo watermark, vignette + scanlines) plus
a `zones.lua` naming the content rectangles the consumer draws into.

This is the "break the flat-rect ceiling" path: ISUI has no rounded
corners / gradients / shadows, but it can stretch a texture, so the chrome
is rendered once here with `System.Drawing` (real `LinearGradientBrush`,
`PathGradientBrush`, `GraphicsPath` arcs) and drawn as a single blit at
runtime.

Nothing here ships inside the KeyasLib mod. Run it on your machine, drop
the two outputs into **your** mod, load them with `KeyasUI.registerSkin`.

## Requirements

Windows + .NET (`System.Drawing`). Every PZ modder on Windows already has it.

## Usage

```
powershell -ExecutionPolicy Bypass -File generate_skin.ps1 `
    -Spec .\spec.xcyos.ps1 `
    -OutDir ..\..\examples\xcyos `
    -Name chrome
```

Outputs `chrome.png` and `zones.lua` in `-OutDir`.

## The spec

`-Spec` is a `.ps1` that **returns a hashtable**. See `spec.xcyos.ps1` for
the full set of keys (all optional except `panes` / `railApps`, which
decide what zones exist). Highlights:

| key | meaning |
|---|---|
| `bakeW`, `bakeH` | authoring canvas size; all zone coords are in this space |
| `bezel`, `bezelRadius` | CRT frame colour and corner radius |
| `desktopInner/Outer` | radial desktop gradient stops |
| `railApps` | `@(,@("LABEL","glyphKind"))` per rail item (`monitor\|page\|folder\|gear`) |
| `stripe` | 4 hex colours for the rainbow accent behind the rail |
| `logo` | absolute path to a PNG watermark (or omit) |
| `winX/Y/W/H`, `winFace` | the window rectangle and body colour |
| `titleTop/Bot/Ink`, `titleText` | title-bar gradient + text |
| `panes` | `@(,@("zoneName", x, y, w, h))` window-relative; emitted zone is the pane interior inset 14 px |
| `statusLeft/Right` | status-bar text |
| `scanAlpha`, `vignetteAlpha` | 0-255 strength of the baked CRT overlay |

## Using the output in your mod

```
YourMod/media/ui/YourMod/xcyos_chrome.png       <- the baked PNG
YourMod/media/lua/client/YourMod/xcyos_zones.lua <- the emitted zones.lua
```

```lua
require "KeyasLib/KeyasUI"
local spec = require "YourMod/xcyos_zones"
KeyasUI.registerSkin("xcyos", {
    chromePath = "media/ui/YourMod/xcyos_chrome.png",
    spec = spec,
})

MyWindow = KeyasUI.Window:derive("MyWindow")
function MyWindow:new()
    return KeyasUI.Window.new(self, 0, 0, 100, 100, { skin = "xcyos" })
end
function MyWindow:onRenderContent()
    local x, y, w, h = self:zone("detailPane")
    KeyasUI.text(self, "hello", x, y, { r = 0.1, g = 0.1, b = 0.08, a = 1 })
end
```

See `examples/xcyos/demo.lua` for a fuller example (rail switching, a baked
close button wired with `addZoneButton`).

## Regenerating after a design change

Edit the spec, re-run. Output is deterministic from the spec + any `logo`
PNG. Commit the new `chrome.png` / `zones.lua` into your consumer mod.

## Adding parts the baker doesn't know about

`generate_skin.ps1` draws a fixed set of retro-OS parts. If you need
something it doesn't do (a second window, a different rail layout, custom
art), the simplest route is: bake the base with this tool, then composite
your extra art onto `chrome.png` in an image editor and add the matching
zone rows to `zones.lua` by hand. Or fork `SkinBaker.Build` - it's ~150
lines of straightforward GDI+.
