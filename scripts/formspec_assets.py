"""Select original-resolution VoxeLibre GUI PNGs for the portable LÖVR host.

Keep the 16x16 world atlas independent. GUI assets retain upstream PNG bytes,
including animation strips, without importing thousands of world textures.
"""
from __future__ import annotations

from pathlib import Path
import re

# Strictly bounded first group: actual inventory/stonecutter UI images.
PREFIXES = ("mcl_inventory_", "mcl_stonecutter_", "mcl_formspec_")
SAFE = re.compile(r"[a-zA-Z0-9_.-]+\.png\Z")


def images(game: Path) -> list[Path]:
    directory = game / "textures"
    if not directory.is_dir():
        return []
    result = sorted(
        p for p in directory.glob("*.png")
        if p.is_file() and SAFE.fullmatch(p.name)
        and p.name.startswith(PREFIXES)
    )
    if len(result) > 256:
        raise ValueError("too many original GUI images")
    return result


def manifest(files: list[Path]) -> str:
    """Encode verified pixel dimensions as data, not a Lua code expression."""
    lines = [
        "-- Original source-resolution UI textures from pinned VoxeLibre.",
        "-- This manifest lists only PNGs bundled into visual/formspec/.",
        "return {",
    ]
    if files:
        from PIL import Image
    for path in files:
        if not SAFE.fullmatch(path.name) or not path.name.startswith(PREFIXES):
            raise ValueError("unsafe GUI texture filename: " + path.name)
        with Image.open(path) as image:
            if image.format != "PNG":
                raise ValueError("source UI asset is not PNG: " + path.name)
            w, h = image.size
        if not (1 <= w <= 4096 and 1 <= h <= 4096):
            raise ValueError("invalid source image dimensions: " + path.name)
        lines.append(f' ["{path.name}"] = {{width={w},height={h}}},')
    lines.extend(["}", ""])
    return "\n".join(lines)
