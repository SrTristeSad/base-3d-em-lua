#!/usr/bin/env python3
"""Validate that release atlases use the pinned upstream bytes, not stand-ins."""
from pathlib import Path
from io import BytesIO
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from build_lua_engine_atlas import create, create_upstream, tile_names  # noqa: E402
from package_lua_engine import build  # noqa: E402
from PIL import Image  # noqa: E402

source = Path("lua-engine/core/atlas.lua")
game = Path("games/voxelibre")
assert (game / "textures/default_stone.png").is_file(), (
    "VoxeLibre submodule not checked out")
names = tile_names(source)
assert len(names) == 20
assert names[3] == "default_stone.png"
assert names[11] == "mcl_core_water_source_animation.png"
assert names[16] == "default_glass.png"
assert names[18] == "mcl_core_lava_source_animation.png"
pixels = create_upstream(source, game)
assert pixels == create_upstream(source, game), "upstream atlas must be deterministic"
assert pixels != create(source, None), "release cannot silently use placeholders"
with Image.open(BytesIO(pixels)) as atlas:
    atlas.load()
    assert atlas.size == (64, 80) and atlas.mode == "RGBA"
    with Image.open(game / "textures/default_stone.png") as original:
        tile = original.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((48, 0, 64, 16)).tobytes() == tile.tobytes()
    with Image.open(game / "textures/default_glass.png") as glass:
        raw = glass.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((0, 64, 16, 80)).tobytes() == raw.tobytes()
    with Image.open(game / "textures/mcl_core_lava_source_animation.png") as lava:
        first = lava.convert("RGBA")
        if first.height > first.width:
            first = first.crop((0, 0, first.width, first.width))
        first = first.resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((32, 64, 48, 80)).tobytes() == first.tobytes()
    with Image.open(game / "textures/default_dirt.png") as dirt:
        base = dirt.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
    with Image.open(game / "textures/mcl_dirt_grass_shadow.png") as shadow:
        layer = shadow.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
    grass = Image.alpha_composite(base, layer)
    assert atlas.crop((0, 32, 16, 48)).tobytes() == grass.tobytes()
    with Image.open(game / "textures/mcl_core_water_source_animation.png") as water:
        frame = water.convert("RGBA")
        if frame.height > frame.width:
            frame = frame.crop((0, 0, frame.width, frame.width))
        frame = frame.resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((48, 32, 64, 48)).tobytes() == frame.tobytes()
assert create(source, game, True) == pixels
try:
    create(source, Path("nonexistent-upstream"), True)
except FileNotFoundError:
    pass
else:
    raise AssertionError("strict upstream mode silently used placeholders")
with TemporaryDirectory() as work:
    target = Path(work) / "Motor-Lua-Real-Textures.lovr"
    build(Path("lua-engine"), target, game, True)
    with ZipFile(target) as archive:
        assert archive.read("visual/atlas.png") == pixels
        assert b"pinned VoxeLibre submodule" in archive.read("visual/ASSET-SOURCES.txt")
        assert b"Upstream commit:" in archive.read("visual/ASSET-SOURCES.txt")
        assert archive.read("visual/licenses/VoxeLibre-LICENSE.txt")
        assert archive.read("visual/licenses/VoxeLibre-CREDITS.md")
        assert archive.read("visual/licenses/mcl_core-README.txt")
        assert "core/mesher.lua" in archive.namelist()
print("LUA ENGINE UPSTREAM TEXTURE ATLAS PASS")
