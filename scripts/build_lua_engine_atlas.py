#!/usr/bin/env python3
"""Generate a tiny deterministic 4x4 placeholder atlas (stdlib only).

Texture identifiers match real VoxeLibre tile names, but these pixels are
generated for the standalone demo. They are NOT upstream VoxeLibre textures.
"""
from __future__ import annotations

from pathlib import Path
from io import BytesIO
import re
import struct
import zlib

BASE = (
    (234, 30, 226), (104, 160, 65), (119, 76, 47), (126, 129, 134),
    (215, 193, 131), (112, 115, 111), (120, 123, 128), (133, 133, 127),
    (122, 100, 65), (125, 87, 52), (53, 117, 64), (53, 115, 182),
    (175, 140, 86), (142, 135, 107), (134, 124, 112), (226, 235, 239),
)


def tile_names(source: Path) -> list[str]:
    text = source.read_text(encoding="utf-8")
    content = text.split("A.tiles={", 1)[1].split("\n}", 1)[0]
    result = re.findall(r"'([^']+\.png)'", content)
    if len(result) < 16 or len(set(result)) != len(result):
        raise ValueError("expected unique Lua atlas texture names")
    return result


def png(width: int, height: int, rgba: bytes) -> bytes:
    if len(rgba) != width * height * 4:
        raise ValueError("invalid raw pixel count")
    raw = b"".join(b"\0" + rgba[y * width * 4:(y + 1) * width * 4]
                   for y in range(height))
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6,
                                       0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(raw, 9)) +
            chunk(b"IEND", b""))


def _open_tile(game: Path, name: str):
    # Strictly resolve source files inside the pinned VoxeLibre texture tree.
    if not name.endswith(".png") or "/" in name or "\\\\" in name:
        raise ValueError("unsafe upstream texture identifier: " + name)
    from PIL import Image
    path = game / "textures" / name
    if not path.is_file():
        raise FileNotFoundError("missing pinned VoxeLibre texture: " + str(path))
    with Image.open(path) as picture:
        rgba = picture.convert("RGBA")
    # Animated Luanti texture strips contain multiple square frames.
    # Only the FIRST frame is currently rendered in the Lua GPU port.
    if rgba.height > rgba.width:
        rgba = rgba.crop((0, 0, rgba.width, rgba.width))
    return rgba.resize((16, 16), Image.Resampling.NEAREST)


def create_upstream(source: Path, game: Path) -> bytes:
    """Make the first real-texture atlas; no silent fallback if assets are missing."""
    from PIL import Image
    names = tile_names(source)
    atlas = Image.new("RGBA", (64, 16 * ((len(names) + 3) // 4)), (0, 0, 0, 0))
    # The only non-upstream tile is our explicit magenta missing-texture slot.
    fallback = Image.open(BytesIO(create_placeholder(source))).convert("RGBA")
    for i, name in enumerate(names):
        if i == 0:
            piece = fallback.crop((0, 0, 16, 16))
        elif name == "mcl_core_grass_block_side.png":
            piece = _open_tile(game, "default_dirt.png")
            shadow = _open_tile(game, "mcl_dirt_grass_shadow.png")
            piece = Image.alpha_composite(piece, shadow)
        else:
            piece = _open_tile(game, name)
        atlas.paste(piece, ((i % 4) * 16, (i // 4) * 16))
    output = BytesIO()
    atlas.save(output, format="PNG", optimize=True)
    return output.getvalue()


def create(source: Path, game: Path | None = None,
           require_upstream: bool = False) -> bytes:
    if game is not None and (game / "textures").is_dir():
        return create_upstream(source, game)
    if require_upstream:
        raise FileNotFoundError(
            "the pinned VoxeLibre submodule textures are required; "
            "checkout with --recurse-submodules")
    return create_placeholder(source)


def create_placeholder(source: Path) -> bytes:
    names = tile_names(source)
    width, height = 64, 16 * ((len(names) + 3) // 4)
    pixels = bytearray(width * height * 4)
    for i, _ in enumerate(names):
        base = BASE[i % len(BASE)]
        for y in range(16):
            for x in range(16):
                noise = (((x * 1103515245 + y * 12345 + (i + 1) * 7919) ^
                          ((x + 17) * (y + 31) * 211)) >> 4) & 31
                shade = noise - 15
                color = list(base)
                if i == 0:  # unmistakable missing-texture indicator
                    color = [240, 0, 240] if ((x // 4 + y // 4) % 2) else [20, 20, 20]
                elif i == 8:  # temporary grass-over-dirt side pattern
                    color = list(BASE[1] if y < 4 else BASE[2])
                elif i in (6, 7, 13) and noise > 23:
                    color = {6: [30, 34, 38], 7: [174, 126, 92],
                             13: [222, 185, 72]}[i]
                elif i == 9 and x % 5 in (0, 1):
                    color = [87, 60, 38]
                if i not in (0,):
                    color = [max(0, min(255, channel + shade)) for channel in color]
                dx = (i % 4) * 16 + x
                dy = (i // 4) * 16 + y
                p = (dy * width + dx) * 4
                pixels[p:p + 4] = bytes((*color, 255))
    return png(width, height, bytes(pixels))


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--atlas", type=Path, default=Path("lua-engine/core/atlas.lua"))
    parser.add_argument("--output", type=Path, default=Path("dist/atlas.png"))
    parser.add_argument("--game", type=Path, default=None)
    parser.add_argument("--require-upstream", action="store_true")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(create(args.atlas, args.game, args.require_upstream))
