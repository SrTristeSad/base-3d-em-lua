#!/usr/bin/env python3
"""Generate a standalone LÖVR demo from lua-engine/, without touching VoxeLibre."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
from build_lua_engine_atlas import create as build_atlas

REQUIRED = ("main.lua", "conf.lua", "core/map.lua",
            "core/vector.lua", "core/runtime.lua", "core/storage.lua",
            "core/itemstack.lua", "core/inventory.lua", "core/modloader.lua",
            "core/modenvironment.lua", "core/modstorage.lua",
            "core/bitops.lua", "core/pcgrandom.lua", "core/voxel.lua",
            "core/worldgen.lua", "core/particles.lua",
            "core/nodedrops.lua", "core/pseudorandom.lua",
            "core/atlas.lua", "core/mesher.lua", "core/renderer.lua")


def build(source: Path, output: Path, game: Path | None = None,
          require_upstream: bool = False) -> None:
    source = source.resolve()
    for name in REQUIRED:
        if not (source / name).is_file():
            raise ValueError("missing Lua engine file: " + name)
    if game is not None:
        game = game.resolve()
    original = game is not None and (game / "textures").is_dir()
    if require_upstream and not original:
        raise FileNotFoundError("VoxeLibre textures unavailable: checkout submodule")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as z:
        for file in sorted(source.rglob("*")):
            if file.is_file() and file.suffix == ".lua":
                z.write(file, file.relative_to(source).as_posix())
        z.writestr("visual/atlas.png",
                   build_atlas(source / "core/atlas.lua", game, require_upstream))
        if original:
            # The image pixels are from the pinned submodule, not generated
            # lookalikes. Preserve upstream licensing and credit references.
            license_file = game / "LICENSE.txt"
            credits_file = game / "CREDITS.md"
            core_readme = game / "mods/ITEMS/mcl_core/README.txt"
            for filename, item in (
                ("VoxeLibre-LICENSE.txt", license_file),
                ("VoxeLibre-CREDITS.md", credits_file),
                ("mcl_core-README.txt", core_readme),
            ):
                if not item.is_file():
                    raise FileNotFoundError("required upstream attribution: " + str(item))
                z.write(item, "visual/licenses/" + filename)
        z.writestr("visual/ASSET-SOURCES.txt",
            "Atlas source: " + ("pinned VoxeLibre submodule textures/" if original
                                 else "generated placeholders (no upstream assets)") +
            "\\nWater: first animation frame only; no animation in Lua renderer.\\n" +
            "Grass side: upstream dirt + grass shadow composite.\\n" +
            "See visual/licenses/ for upstream credits and licensing if present.\\n")
    with ZipFile(output) as z:
        assert all(name in z.namelist() for name in REQUIRED)
        assert "visual/atlas.png" in z.namelist()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=Path("lua-engine"))
    ap.add_argument("--output", type=Path, default=Path("dist/Motor-Lua-Demo.lovr"))
    ap.add_argument("--game", type=Path, default=Path("games/voxelibre"))
    ap.add_argument("--require-upstream-textures", action="store_true")
    args = ap.parse_args()
    build(args.source, args.output, args.game, args.require_upstream_textures)
