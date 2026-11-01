#!/usr/bin/env python3
"""Validate that release atlases use the pinned upstream bytes, not stand-ins."""
from pathlib import Path
from io import BytesIO
from tempfile import TemporaryDirectory
from zipfile import ZipFile
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from build_lua_engine_atlas import (create, create_upstream, tile_names,
                                     upstream_tile_names, atlas_manifest)  # noqa: E402
from package_lua_engine import build  # noqa: E402
from PIL import Image  # noqa: E402

source = Path("lua-engine/core/atlas.lua")
game = Path("games/voxelibre")
assert (game / "textures/default_stone.png").is_file(), (
    "VoxeLibre submodule not checked out")
base_names = tile_names(source)
assert len(base_names) == 20
names = upstream_tile_names(source, game)
all_upstream = {p.name for p in (game / "textures").glob("*.png")}
assert len(all_upstream) > 2800, "submodule must contain the full texture catalog"
assert all_upstream.issubset(set(names)), "every pinned source image must be indexed"
assert len(names) == len(all_upstream) + 2, "only two synthetic atlas slots expected"
assert names[:20] == base_names and names[20:] == sorted(names[20:])
assert names == upstream_tile_names(source, game)
assert atlas_manifest(names, 64).count('  "') == len(names)

assert names[3] == "default_stone.png"
assert names[11] == "mcl_core_water_source_animation.png"
assert names[16] == "default_glass.png"
assert names[18] == "mcl_core_lava_source_animation.png"
pixels = create_upstream(source, game)
assert pixels == create_upstream(source, game), "upstream atlas must be deterministic"
assert pixels != create(source, None), "release cannot silently use placeholders"
with Image.open(BytesIO(pixels)) as atlas:
    atlas.load()
    assert atlas.size == (1024, 16 * ((len(names) + 63) // 64)) and atlas.mode == "RGBA"
    with Image.open(game / "textures/default_stone.png") as original:
        tile = original.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((48, 0, 64, 16)).tobytes() == tile.tobytes()
    with Image.open(game / "textures/default_glass.png") as glass:
        raw = glass.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((256, 0, 272, 16)).tobytes() == raw.tobytes()
    with Image.open(game / "textures/mcl_core_lava_source_animation.png") as lava:
        first = lava.convert("RGBA")
        if first.height > first.width:
            first = first.crop((0, 0, first.width, first.width))
        first = first.resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((288, 0, 304, 16)).tobytes() == first.tobytes()
    with Image.open(game / "textures/default_dirt.png") as dirt:
        base = dirt.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
    with Image.open(game / "textures/mcl_dirt_grass_shadow.png") as shadow:
        layer = shadow.convert("RGBA").resize((16, 16), Image.Resampling.NEAREST)
    grass = Image.alpha_composite(base, layer)
    assert atlas.crop((128, 0, 144, 16)).tobytes() == grass.tobytes()
    with Image.open(game / "textures/mcl_core_water_source_animation.png") as water:
        frame = water.convert("RGBA")
        if frame.height > frame.width:
            frame = frame.crop((0, 0, frame.width, frame.width))
        frame = frame.resize((16, 16), Image.Resampling.NEAREST)
        assert atlas.crop((176, 0, 192, 16)).tobytes() == frame.tobytes()
    # A far-later index must also contain the EXACT upstream pixels.
    sampled_name = names[-1]
    with Image.open(game / "textures" / sampled_name) as sample:
        tile = sample.convert("RGBA")
        if tile.height > tile.width:
            tile = tile.crop((0, 0, tile.width, tile.width))
        tile = tile.resize((16, 16), Image.Resampling.NEAREST)
    slot = len(names) - 1
    rect = ((slot % 64) * 16, (slot // 64) * 16,
            (slot % 64 + 1) * 16, (slot // 64 + 1) * 16)
    assert atlas.crop(rect).tobytes() == tile.tobytes(), sampled_name
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
        manifest = archive.read("core/atlas_manifest.lua").decode("utf-8")
        assert manifest == atlas_manifest(names, 64)
        assert archive.read("visual/ATLAS-INDEX.txt").decode("utf-8").splitlines() == names
        assert "columns=64" in manifest
        assert f'  "{names[-1]}",' in manifest

print("LUA ENGINE UPSTREAM TEXTURE ATLAS PASS")
