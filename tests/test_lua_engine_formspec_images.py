#!/usr/bin/env python3
"""Original, unresized VoxeLibre formspec textures survive LÖVR packaging."""
from pathlib import Path
from tempfile import TemporaryDirectory
from zipfile import ZipFile
from io import BytesIO
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))
from formspec_assets import images, manifest  # noqa: E402
from package_lua_engine import build  # noqa: E402
from PIL import Image  # noqa: E402

game = Path("games/voxelibre")
source = Path("lua-engine")
files = images(game)
assert len(files) >= 10, "upstream inventory images are missing"
names = [f.name for f in files]
assert names == sorted(names)
assert "mcl_inventory_stonecutter.png" in names
assert "mcl_stonecutter_saw.png" in names
assert len(set(names)) == len(names)
lua = manifest(files)
assert lua.startswith("-- Original source-resolution UI textures")
with Image.open(game / "textures/mcl_stonecutter_saw.png") as source_image:
    assert source_image.height % 3 == 0, (
        "VoxeLibre saw animation must contain three complete frames")
    assert f"width={source_image.width},height={source_image.height}" in lua

with TemporaryDirectory() as tmp:
    output = Path(tmp) / "test-original-images.lovr"
    build(source, output, game, require_upstream=True)
    with ZipFile(output) as z:
        assert z.read("core/formspec_original_manifest.lua").decode() == lua
        assert all("visual/formspec/" + p.name in z.namelist()
                   for p in files)
        for name in ("mcl_inventory_stonecutter.png",
                     "mcl_stonecutter_saw.png",
                     "mcl_inventory_background9.png"):
            path = game / "textures" / name
            raw = path.read_bytes()
            assert z.read("visual/formspec/" + name) == raw, (
                name + " was modified or resized")
            with Image.open(BytesIO(z.read("visual/formspec/" + name))) as original:
                with Image.open(path) as upstream:
                    assert original.size == upstream.size
                    assert original.tobytes() == upstream.tobytes()
        assert len([n for n in z.namelist()
                    if n.startswith("visual/formspec/")]) == len(files)
    # Packaging must not leak upstream UI resources into a source-only
    # standalone demo where the original game was never checked out.
    basic = Path(tmp) / "test-placeholder-images.lovr"
    build(source, basic, None)
    with ZipFile(basic) as z:
        assert z.read("core/formspec_original_manifest.lua").decode() == manifest([])
        assert not any(n.startswith("visual/formspec/") for n in z.namelist())

print(f"LUA ENGINE ORIGINAL VOXELIBRE FORMSPEC PNG PASS: {len(files)} assets")
