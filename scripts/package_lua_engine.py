#!/usr/bin/env python3
"""Generate a standalone LÖVR demo from lua-engine/, without touching VoxeLibre."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
import subprocess
from formspec_assets import images as gui_images, manifest as gui_manifest
from build_lua_engine_atlas import (create as build_atlas, tile_names,
    upstream_tile_names, atlas_columns, atlas_manifest)

REQUIRED = ("main.lua", "conf.lua", "core/map.lua",
            "core/vector.lua", "core/runtime.lua", "core/storage.lua",
            "core/itemstack.lua", "core/inventory.lua", "core/modloader.lua",
            "core/modenvironment.lua", "core/modstorage.lua", "core/authchat.lua",
            "core/bitops.lua", "core/pcgrandom.lua", "core/voxel.lua",
            "core/worldgen.lua", "core/particles.lua",
            "core/nodedrops.lua", "core/nodesearch.lua", "core/lighting.lua", "core/pseudorandom.lua",
            "core/atlas.lua", "core/mesher.lua", "core/nodebox.lua",
            "core/physics.lua", "core/playerphysics.lua",
            "core/playeractions.lua", "core/digging.lua",
            "core/playerstorage.lua", "core/demohud.lua",
            "core/demoinventory.lua", "core/renderer.lua",
            "core/formspecview.lua", "core/formspecsprites.lua",
            "core/formspecnine.lua", "core/formspecbackground.lua", "core/formspecscrollbar.lua")


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
    revision = ""
    if original:
        result = subprocess.run(
            ["git", "-C", str(game), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True)
        revision = result.stdout.strip()
        if len(revision) != 40:
            raise ValueError("invalid pinned upstream Git revision")
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    names = (upstream_tile_names(source / "core/atlas.lua", game)
             if original else tile_names(source / "core/atlas.lua"))
    columns = atlas_columns(game if original else None)
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as z:
        for file in sorted(source.rglob("*")):
            if file.is_file() and file.suffix == ".lua":
                z.write(file, file.relative_to(source).as_posix())
        z.writestr("visual/atlas.png",
                   build_atlas(source / "core/atlas.lua", game, require_upstream))
        # Both GPU pixels and Lua lookup are derived from the SAME ordered names.
        z.writestr("core/atlas_manifest.lua", atlas_manifest(names, columns))
        z.writestr("visual/ATLAS-INDEX.txt", "\n".join(names) + "\n")
        originals = gui_images(game) if original else []
        z.writestr("core/formspec_original_manifest.lua",
                   gui_manifest(originals))
        for asset in originals:
            # Preserve full source dimensions, alpha and every animation frame.
            z.write(asset, "visual/formspec/" + asset.name)
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
            ("\\nUpstream commit: " + revision if original else "") +
            "\\nAtlas tile count: " + str(len(names)) +
            "\\nAtlas columns: " + str(columns) +
            "\nWater: first animation frame only; no animation in Lua renderer.\\n" +
            "Grass side: upstream dirt + grass shadow composite.\\n" +
            "See visual/licenses/ for upstream credits and licensing if present.\\n")
    with ZipFile(output) as z:
        assert all(name in z.namelist() for name in REQUIRED)
        assert "visual/atlas.png" in z.namelist()
        assert "core/atlas_manifest.lua" in z.namelist()
        assert "core/formspec_original_manifest.lua" in z.namelist()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=Path("lua-engine"))
    ap.add_argument("--output", type=Path, default=Path("dist/Motor-Lua-Demo.lovr"))
    ap.add_argument("--game", type=Path, default=Path("games/voxelibre"))
    ap.add_argument("--require-upstream-textures", action="store_true")
    args = ap.parse_args()
    build(args.source, args.output, args.game, args.require_upstream_textures)
