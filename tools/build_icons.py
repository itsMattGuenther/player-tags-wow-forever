#!/usr/bin/env python3
"""Builds the addon's textures from the glyph definitions below.

Outputs (into PlayerTags/Media):
  glyphs.tga  512x256 atlas, 8 columns x 4 rows of 64px cells, white on transparent
  icon.tga    64x64 addon list icon
  minimap.tga 64x64 round icon for the minimap button

The glyph order here is the glyph index used by Tags.lua. Append new glyphs at
the end; never reorder, or saved custom tags will point at the wrong picture.

Needs rsvg-convert and Pillow. Run:  python3 tools/build_icons.py
"""
import struct
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "PlayerTags" / "Media"
CELL, COLS, ROWS = 64, 8, 4

# name, SVG body on a 24x24 grid (stroked, never filled)
GLYPHS = [
    ("helpful", '<path d="M12 20.5s-7.5-4.6-7.5-10.2A4.3 4.3 0 0 1 12 7.6a4.3 4.3 0 0 1 7.5 2.7c0 5.6-7.5 10.2-7.5 10.2z"/>'),
    ("company", '<circle cx="12" cy="12" r="8.5"/><path d="M8.5 14c.9 1.4 2.1 2 3.5 2s2.6-.6 3.5-2M9 9.6v.4M15 9.6v.4"/>'),
    ("generous", '<path d="M4.5 11h15v9h-15zM3 7.5h18V11H3zM12 7.5V20"/><path d="M12 7.5C10.5 4 7 4 7 6s2.5 1.5 5 1.5zm0 0C13.5 4 17 4 17 6s-2.5 1.5-5 1.5z"/>'),
    ("reliable", '<path d="M12 3l7.5 2.8v5.4c0 4.6-3.2 7.9-7.5 9.8-4.3-1.9-7.5-5.2-7.5-9.8V5.8z"/><path d="M8.7 12l2.3 2.3 4.3-4.6"/>'),
    ("patient", '<path d="M7 3h10M7 21h10M8 3v3.5c0 2 4 3.5 4 5.5s-4 3.5-4 5.5V21M16 3v3.5c0 2-4 3.5-4 5.5s4 3.5 4 5.5V21"/>'),
    ("tank", '<path d="M12 3l7.5 2.8v5.4c0 4.6-3.2 7.9-7.5 9.8-4.3-1.9-7.5-5.2-7.5-9.8V5.8z"/><path d="M12 3v18M4.5 10.5h15"/>'),
    ("healer", '<path d="M9.5 4h5v5.5H20v5h-5.5V20h-5v-5.5H4v-5h5.5z"/>'),
    ("damage", '<path d="M20 4h-3.5l-8 8 3.5 3.5 8-8z"/><path d="M6.5 11.5l6 6M8 16l-4 4"/>'),
    ("pvp", '<path d="M4 17.5L2.5 8l5 4L12 4.5l4.5 7.5 5-4L20 17.5z"/><path d="M4.5 21h15"/>'),
    ("leader", '<path d="M6 21V4M6 4.5h12l-3 4 3 4H6"/>'),
    ("hitrun", '<path d="M10 4H5v16h5"/><path d="M14 8l4 4-4 4M18 12H9"/>'),
    ("quiet", '<path d="M4 5h16v11h-8l-4.5 4v-4H4z"/><path d="M8.5 10.5h.01M12 10.5h.01M15.5 10.5h.01"/>'),
    ("crafter", '<path d="M13.5 3.5l7 7-2.5 2.5-7-7z"/><path d="M12.5 9L4 17.5 6.5 20l8.5-8.5"/>'),
    ("rival", '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2.2"/><path d="M12 2v4M12 18v4M2 12h4M18 12h4"/>'),
    ("newbie", '<path d="M12 21v-9M12 12c0-4-3-6-7-6 0 4 3 6 7 6zM12 14.5c0-3 2.5-5 6.5-5 0 3.500-2.5 5-6.5 5z"/>'),
    ("afk", '<path d="M19 14.5A8 8 0 1 1 9.5 5a6.5 6.5 0 0 0 9.5 9.5z"/>'),
    ("rude", '<path d="M4 5h16v11h-8l-4.5 4v-4H4z"/><path d="M12 7.8v3.4M12 13.4h.01"/>'),
    ("leaver", '<path d="M9.5 14.5l-2.2 2.2a3 3 0 0 1-4.2-4.2l3-3a3 3 0 0 1 3.4-.6"/><path d="M14.5 9.5l2.2-2.2a3 3 0 0 1 4.2 4.2l-3 3a3 3 0 0 1-3.4.6"/><path d="M8 3.5V6M3.5 8H6M16 20.5V18M20.5 16H18"/>'),
    ("ninja", '<path d="M3 9.5c3-1.7 6-2.5 9-2.5s6 .8 9 2.5c0 4.5-2.4 7.5-4.8 7.5-1.900 0-2.300-2-4.200-2s-2.300 2-4.200 2C5.400 17 3 14 3 9.500z"/><path d="M7.5 11.2l2.5.9M16.5 11.2l-2.5.9"/>'),
    ("ganker", '<path d="M12 3.5a7.5 7.5 0 0 0-4.5 13.5v3h9v-3A7.5 7.5 0 0 0 12 3.5z"/><path d="M9 11.5h.01M15 11.5h.01M10.5 20v-2M13.5 20v-2"/>'),
    ("scammer", '<circle cx="12" cy="12" r="8.5"/><path d="M14.5 9.3c-.8-1-4.6-1.200-4.600.9 0 2.200 4.600 1.300 4.600 3.500 0 2-3.800 1.900-4.600.900M12 6.500v11"/><path d="M4.500 19.500l15-15"/>'),
    ("griefer", '<path d="M12 21c-3.5 0-6-2.5-6-6 0-3 2-4.5 3-7 .5 2 1.500 3 2.500 3.500C11 8 12 5 14.500 3c0 3 3.500 5.500 3.500 10.500 0 4-2.500 7.500-6 7.500z"/>'),
    ("star", '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 16.900l-5.200 2.800 1-5.900-4.300-4.100 5.900-.800z"/>'),
    ("eye", '<path d="M2.5 12S6 5.5 12 5.5 21.500 12 21.500 12 18 18.500 12 18.500 2.500 12 2.500 12z"/><circle cx="12" cy="12" r="2.8"/>'),
    ("music", '<path d="M9 18V5.5l10-2V16"/><circle cx="6.5" cy="18" r="2.5"/><circle cx="16.5" cy="16" r="2.5"/>'),
    ("book", '<path d="M5 4.5h11a3 3 0 0 1 3 3V20H8a3 3 0 0 1-3-3zM5 17a3 3 0 0 1 3-3h11M9 8.500h6"/>'),
    ("coin", '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.2"/>'),
    ("bolt", '<path d="M13.5 2.5L5 13.5h6l-1 8 8.500-11h-6z"/>'),
    ("paw", '<circle cx="6.5" cy="10.5" r="1.8"/><circle cx="10" cy="6.500" r="1.800"/><circle cx="14" cy="6.500" r="1.800"/><circle cx="17.500" cy="10.500" r="1.800"/><path d="M12 12.500c-3 0-5 2.500-5 4.500 0 1.500 1.500 2.500 3 2 1.300-.400 2.700-.400 4 0 1.500.500 3-.500 3-2 0-2-2-4.500-5-4.500z"/>'),
    ("anchor", '<circle cx="12" cy="5" r="2.5"/><path d="M12 7.5V21M5 13c0 4.500 3 8 7 8s7-3.500 7-8M8.500 11h7"/>'),
    ("question", '<circle cx="12" cy="12" r="8.5"/><path d="M9.5 9.500a2.500 2.500 0 1 1 3.700 2.200c-.800.400-1.200 1-1.200 1.800M12 16.500h.01"/>'),
    ("diamond", '<path d="M12 3l8 9-8 9-8-9z"/>'),
]
assert len(GLYPHS) == COLS * ROWS, len(GLYPHS)


def render(svg: str, out_png: Path, width: int, height: int) -> Image.Image:
    subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(out_png)],
        input=svg.encode(), check=True,
    )
    return Image.open(out_png).convert("RGBA")


def write_tga(img: Image.Image, path: Path) -> None:
    """Uncompressed 32-bit TGA, bottom-left origin: the layout WoW addons ship."""
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x08)
    rows = []
    px = img.load()
    for y in range(h - 1, -1, -1):
        row = bytearray()
        for x in range(w):
            r, g, b, a = px[x, y]
            row += bytes((b, g, r, a))
        rows.append(bytes(row))
    path.write_bytes(header + b"".join(rows))


def build_atlas(tmp: Path) -> Image.Image:
    cells = []
    for i, (_, body) in enumerate(GLYPHS):
        col, row = i % COLS, i // COLS
        # 24-unit glyph scaled x2 = 48px, centred in the 64px cell (8px margin stops bleed)
        cells.append(f'<g transform="translate({col * CELL + 8} {row * CELL + 8}) scale(2)">{body}</g>')
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{COLS * CELL}" height="{ROWS * CELL}" '
        f'viewBox="0 0 {COLS * CELL} {ROWS * CELL}">'
        '<g fill="none" stroke="#fff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">'
        + "".join(cells) + "</g></svg>"
    )
    img = render(svg, tmp / "glyphs.png", COLS * CELL, ROWS * CELL)
    # pure white everywhere so tinting in game never shows a dark fringe
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            px[x, y] = (255, 255, 255, px[x, y][3])
    return img


def build_icon(tmp: Path) -> Image.Image:
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
        '<rect x="2" y="2" width="60" height="60" rx="10" fill="#0D1117" stroke="#FFD100" stroke-width="3"/>'
        '<g transform="translate(11 11) scale(1.75)" fill="none" stroke="#FFD100" stroke-width="2.2" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M4 12.800V4.500h8.300l7.700 7.700-8.300 8.300z"/><circle cx="8.300" cy="8.800" r="1.300"/></g></svg>'
    )
    return render(svg, tmp / "icon.png", 64, 64)


def build_minimap_icon(tmp: Path) -> Image.Image:
    """The same tag on a dark disc. The game draws its gold ring around it."""
    svg = (
        '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
        '<circle cx="32" cy="32" r="31" fill="#0D1117"/>'
        '<g transform="translate(11.9 11.1) scale(1.675)" fill="none" stroke="#FFD100" stroke-width="2.5" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M4 12.800V4.500h8.300l7.700 7.700-8.300 8.300z"/><circle cx="8.300" cy="8.800" r="1.300"/></g></svg>'
    )
    return render(svg, tmp / "minimap.png", 64, 64)


def main() -> int:
    tmp = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tools" / ".build"
    tmp.mkdir(parents=True, exist_ok=True)
    MEDIA.mkdir(parents=True, exist_ok=True)
    atlas = build_atlas(tmp)
    write_tga(atlas, MEDIA / "glyphs.tga")
    write_tga(build_icon(tmp), MEDIA / "icon.tga")
    write_tga(build_minimap_icon(tmp), MEDIA / "minimap.tga")
    # preview on a dark ground, for eyeballing only
    preview = Image.new("RGBA", atlas.size, (16, 21, 27, 255))
    preview.alpha_composite(atlas)
    preview.save(tmp / "glyphs_preview.png")
    print("glyphs:", ", ".join(f"{i}={n}" for i, (n, _) in enumerate(GLYPHS)))
    print("wrote", MEDIA / "glyphs.tga", (MEDIA / "glyphs.tga").stat().st_size, "bytes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
