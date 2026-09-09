#!/usr/bin/env python3
"""
generate_font_atlas.py - build a KeyasUI-compatible bitmap font atlas.

Offline tool only: this script (and its Pillow dependency) never ships
inside the KeyasLib mod. It produces two files per requested size:

    <name>_<size>.png          - the atlas image (drop into your mod's
                                  media/textures/, or wherever your mod's
                                  build packs media/textures from)
    <name>_<size>_metrics.lua  - a Lua module returning the metrics table
                                  KeyasUI.registerFont() expects

Usage
-----
    python3 generate_font_atlas.py --font MyFont.ttf --sizes 12,16,24 \
        --name terminal --out-dir ./out

    python3 generate_font_atlas.py --font MyFont.ttf --sizes 16 \
        --chars-file extra_glyphs.txt --name terminal --out-dir ./out

Then in your mod's Lua:

    local metrics = require "KeyasLib/generated/terminal_16_metrics"
    KeyasUI.registerFont("terminal16", {
        atlasPath = "media/textures/terminal_16.png",
        metrics = metrics,
    })

Glyph placement convention (matches KeyasUI.text() exactly - see
KeyasUI.lua's comment above the glyph-drawing loop):
    x, y, w, h   - source rectangle within the atlas PNG
    xoff, yoff   - offset from the pen position / top of the line to the
                   glyph's top-left ink pixel
    xadv         - how far to advance the pen after drawing this glyph
"""

import argparse
import json
import math
import os
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("ERROR: this tool needs Pillow. Install it with: pip install Pillow", file=sys.stderr)
    sys.exit(1)

DEFAULT_CHARSET = "".join(chr(c) for c in range(0x20, 0x7F))  # printable ASCII
PADDING = 1  # px of transparent padding between packed glyphs, avoids bleed


def parse_args():
    p = argparse.ArgumentParser(description="Generate a KeyasUI bitmap font atlas + metrics.lua")
    p.add_argument("--font", required=True, help="Path to a .ttf/.otf file")
    p.add_argument("--sizes", required=True, help="Comma-separated pixel sizes, e.g. 12,16,24")
    p.add_argument("--name", required=True, help="Base name for output files")
    p.add_argument("--out-dir", default=".", help="Output directory (default: current dir)")
    p.add_argument("--chars", default=None, help="Literal character set to render (default: printable ASCII)")
    p.add_argument("--chars-file", default=None, help="UTF-8 text file; every distinct character in it is added to the charset")
    p.add_argument("--color", default="255,255,255", help="R,G,B to render glyphs in (default: white - tint at runtime via KeyasUI.text's colorRGB)")
    return p.parse_args()


def build_charset(args):
    chars = set(args.chars) if args.chars else set(DEFAULT_CHARSET)
    if args.chars_file:
        with open(args.chars_file, "r", encoding="utf-8") as f:
            chars.update(f.read())
    # Always include space even if the caller's set omits it - text with
    # no spaces at all is a very easy mistake to make when hand-typing
    # a --chars value.
    chars.add(" ")
    return sorted(chars, key=ord)


def render_one_size(font_path, size, chars, color, out_dir, base_name):
    font = ImageFont.truetype(font_path, size)
    ascent, descent = font.getmetrics()
    line_height = ascent + descent

    # Measure every glyph first so we can size the atlas up front instead
    # of guessing and re-packing.
    scratch = Image.new("RGBA", (1, 1))
    draw = ImageDraw.Draw(scratch)

    measurements = {}
    max_w, max_h = 1, 1
    for ch in chars:
        bbox = draw.textbbox((0, 0), ch, font=font)  # (left, top, right, bottom)
        left, top, right, bottom = bbox
        w = max(0, right - left)
        h = max(0, bottom - top)
        try:
            adv = font.getlength(ch)
        except AttributeError:
            adv = draw.textlength(ch, font=font)  # older Pillow fallback
        measurements[ch] = {
            "w": w, "h": h,
            "xoff": left, "yoff": top,
            "xadv": adv,
        }
        max_w = max(max_w, w)
        max_h = max(max_h, h)

    # Simple fixed-cell grid pack: plenty good enough for a few hundred
    # glyphs, and trivially easy to reason about compared to a shelf/
    # bin packer. If you need denser packing for very large character
    # sets, that's a fine place to extend this script.
    cell_w = max_w + PADDING * 2
    cell_h = max_h + PADDING * 2
    cols = max(1, int(math.ceil(math.sqrt(len(chars)))))
    rows = int(math.ceil(len(chars) / cols))
    atlas_w = cols * cell_w
    atlas_h = rows * cell_h

    atlas = Image.new("RGBA", (atlas_w, atlas_h), (0, 0, 0, 0))
    adraw = ImageDraw.Draw(atlas)

    glyphs = {}
    for i, ch in enumerate(chars):
        col = i % cols
        row = i // cols
        cell_x = col * cell_w + PADDING
        cell_y = row * cell_h + PADDING

        m = measurements[ch]
        if m["w"] > 0 and m["h"] > 0:
            # Draw so the glyph's own top-left ink pixel lands exactly at
            # (cell_x, cell_y) - i.e. compensate for textbbox's left/top.
            adraw.text((cell_x - m["xoff"], cell_y - m["yoff"]), ch, font=font, fill=tuple(color) + (255,))

        glyphs[ord(ch)] = {
            "x": cell_x, "y": cell_y,
            "w": m["w"], "h": m["h"],
            "xoff": m["xoff"], "yoff": m["yoff"],
            "xadv": round(m["xadv"], 3),
        }

    png_path = os.path.join(out_dir, f"{base_name}_{size}.png")
    atlas.save(png_path)

    metrics = {"lh": line_height, "base": ascent, "g": glyphs}
    lua_path = os.path.join(out_dir, f"{base_name}_{size}_metrics.lua")
    write_metrics_lua(lua_path, metrics)

    print(f"Wrote {png_path} ({atlas_w}x{atlas_h}, {len(chars)} glyphs) and {lua_path}")


def write_metrics_lua(path, metrics):
    """Writes a Lua module (return {...}) with the metrics table. Hand-
    rolled rather than a generic JSON->Lua dump so the output is stable,
    readable, and diff-friendly if checked into version control."""
    lines = []
    lines.append("-- Auto-generated by tools/font_atlas_gen/generate_font_atlas.py - do not hand-edit.")
    lines.append("return {")
    lines.append(f"    lh = {metrics['lh']},")
    lines.append(f"    base = {metrics['base']},")
    lines.append("    g = {")
    for cp in sorted(metrics["g"].keys()):
        g = metrics["g"][cp]
        lines.append(
            f"        [{cp}] = {{x={g['x']}, y={g['y']}, w={g['w']}, h={g['h']}, "
            f"xoff={g['xoff']}, yoff={g['yoff']}, xadv={g['xadv']}}}, -- {glyph_comment(cp)}"
        )
    lines.append("    },")
    lines.append("}")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def glyph_comment(codepoint):
    try:
        ch = chr(codepoint)
        if ch.isprintable() and ch != " ":
            return f"'{ch}'"
        if ch == " ":
            return "space"
    except ValueError:
        pass
    return f"U+{codepoint:04X}"


def main():
    args = parse_args()
    color = tuple(int(c) for c in args.color.split(","))
    if len(color) != 3:
        print("ERROR: --color must be R,G,B e.g. 255,255,255", file=sys.stderr)
        sys.exit(1)

    chars = build_charset(args)
    os.makedirs(args.out_dir, exist_ok=True)

    sizes = [int(s.strip()) for s in args.sizes.split(",") if s.strip()]
    for size in sizes:
        render_one_size(args.font, size, chars, color, args.out_dir, args.name)


if __name__ == "__main__":
    main()
