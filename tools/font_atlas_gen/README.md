# font_atlas_gen

Offline tool that turns a `.ttf`/`.otf` into a bitmap font atlas PNG plus a
`metrics.lua` file in the shape `KeyasUI.registerFont()` expects. Nothing
in this folder ships inside the KeyasLib mod - run it on your own machine,
commit the generated PNG/Lua into your *consumer* mod, and load them from
there.

Why this exists: Build 42 has no clean way for a mod to register a new
font without overwriting a vanilla one, so KeyasUI draws custom text
glyph-by-glyph from a PNG atlas instead (see `KeyasUI.lua`). This script
is how you build that atlas instead of hand-placing glyphs in GIMP.

## Requirements

- Python 3.8+
- [Pillow](https://pillow.readthedocs.io/): `pip install Pillow`

## Usage

```
python3 generate_font_atlas.py --font MyFont.ttf --sizes 12,16,24 --name terminal --out-dir ./out
```

This writes, for each size:

- `out/terminal_<size>.png` - the atlas
- `out/terminal_<size>_metrics.lua` - a Lua module: `return { lh, base, g = {...} }`

### Options

| Flag | Meaning |
|---|---|
| `--font` (required) | Path to the `.ttf`/`.otf` |
| `--sizes` (required) | Comma-separated pixel sizes, e.g. `12,16,24` |
| `--name` (required) | Base filename for outputs |
| `--out-dir` | Output directory (default: current dir) |
| `--chars` | Literal character set to render (default: printable ASCII 0x20-0x7E) |
| `--chars-file` | A UTF-8 text file; every distinct character found in it is added to the charset. Handy for pulling exactly the accented characters your actual game text uses instead of guessing a Unicode range. |
| `--color` | `R,G,B` to bake into the atlas pixels (default `255,255,255`, i.e. white). Leave it white so `KeyasUI.text()`'s `colorRGB` argument can tint it freely at runtime; only change this if you specifically want a non-tintable atlas. |

## Using the output in your mod

```lua
-- somewhere in your mod's client init, loaded after KeyasLib:
local metrics = require "MyMod/generated/terminal_16_metrics"
KeyasUI.registerFont("terminal16", {
    atlasPath = "media/textures/terminal_16.png", -- wherever you placed the PNG
    metrics = metrics,
})

-- later, in a render():
KeyasUI.text(self, "HELLO WORLD", 10, 10, {r=0.5,g=0.9,b=0.5,a=1}, "terminal16")
```

## Glyph placement convention

Matches `KeyasUI.text()` exactly - it's a simple BMFont-style convention:

- `x, y, w, h` - source rectangle inside the atlas PNG.
- `xoff, yoff` - offset from the current pen position (`xoff`) / the top
  of the line (`yoff`) to the glyph's top-left ink pixel.
- `xadv` - how far to move the pen after drawing this glyph.

If you ever hand-edit a metrics file or write your own generator, keep to
this convention and `KeyasUI.text()` needs no changes.

## Packing

The packer is a plain fixed-cell grid sized to the largest glyph in the
requested character set - simple to reason about, and plenty efficient for
the few hundred glyphs a typical UI font needs. If you're building an atlas
for a huge character set (e.g. full CJK) and file size matters, this is the
function to swap for a real shelf/bin packer (`render_one_size` in
`generate_font_atlas.py`).

## Regenerating after a font change

Just re-run the command - outputs are fully deterministic from the
`.ttf` + arguments, so there's nothing to manually reconcile.
