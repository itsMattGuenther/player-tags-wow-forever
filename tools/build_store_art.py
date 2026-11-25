#!/usr/bin/env python3
"""Builds the store and social images in media/ (not part of the addon zip).

  logo-400.png   CurseForge project logo: exactly 400x400, the addon's own
                 tag icon (the same design as PlayerTags/Media/icon.tga)

Needs rsvg-convert. Run:  python3 tools/build_store_art.py
"""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEDIA = ROOT / "media"

GOLD = "#FFD100"
GROUND = "#0D1117"


def render(svg: str, out: Path, width: int, height: int) -> None:
    subprocess.run(
        ["rsvg-convert", "-w", str(width), "-h", str(height), "-o", str(out)],
        input=svg.encode(), check=True,
    )


def logo() -> str:
    # 400 = the 64px icon's design, redrawn at size: a gold tag on a dark
    # rounded square with a gold rim. Solid ground, so it never reads as a
    # blank square on light or dark pages.
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" viewBox="0 0 400 400">'
        f'<rect width="400" height="400" fill="{GROUND}"/>'
        f'<rect x="14" y="14" width="372" height="372" rx="64" fill="{GROUND}" stroke="{GOLD}" stroke-width="18"/>'
        f'<g transform="translate(72 70) scale(11)" fill="none" stroke="{GOLD}" stroke-width="2.2" '
        'stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M4 12.8V4.5h8.3l7.7 7.7-8.3 8.3z"/></g>'
        # the tag's hole as a solid dot (a stroked circle this small leaves a pinhole)
        f'<circle cx="{72 + 8.3 * 11:.1f}" cy="{70 + 8.8 * 11:.1f}" r="22" fill="{GOLD}"/></svg>'
    )


def main() -> None:
    MEDIA.mkdir(exist_ok=True)
    render(logo(), MEDIA / "logo-400.png", 400, 400)
    print("wrote", MEDIA / "logo-400.png")


if __name__ == "__main__":
    main()
