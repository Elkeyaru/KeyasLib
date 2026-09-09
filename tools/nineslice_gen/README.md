# nineslice_gen

Bakes `keyas_ui_9slice.png` - the one runtime asset `KeyasCSS` needs.

`KeyasCSS` draws rounded rectangles, rounded borders and drop shadows at
any box size by **9-slicing** this atlas: the four corners are blitted at a
fixed pixel size, the four edges are stretched along one axis, the centre
fills the rest. Everything is tinted at draw time, so this single white
atlas covers every colour the UI ever uses.

Unlike `tools/skin_gen` (which bakes a whole fixed window frame), this
atlas is generic and **ships inside the mod** at
`common/media/ui/KeyasLib/keyas_ui_9slice.png`.

## Requirements

Windows + .NET (`System.Drawing`). No other dependency.

## Usage

```
powershell -ExecutionPolicy Bypass -File generate_nineslice.ps1
```

Options:

| Param | Default | Meaning |
|---|---|---|
| `-OutDir` | `..\..\common\media\ui\KeyasLib` | where the PNG is written |
| `-Radius` | `20` | corner radius baked into the ROUND block (px) |
| `-Blur` | `14` | blur radius for the SHADOW block (px) |

## Atlas layout (128 x 64)

| Region | Rect | Use |
|---|---|---|
| ROUND | `(0, 0, 64, 64)` | opaque white rounded square, AA edge, transparent outside - solid fills, border-radius, border rings |
| SHADOW | `(64, 0, 64, 64)` | same square, blurred - `box-shadow` |

## If you change `-Radius`

Update the matching constant in `KeyasCSS.lua`:

```lua
local ROUND = {sx = 0, sy = 0, s = 64, corner = 20}  -- corner == -Radius
```

The `corner` field is the source-pixel size of each corner slice. `SHADOW.corner`
is deliberately larger (28) so the 9-slice captures the blur's falloff.
