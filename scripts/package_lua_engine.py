#!/usr/bin/env python3
"""Generate a standalone LÖVR demo from lua-engine/, without touching VoxeLibre."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse

REQUIRED = ("main.lua", "conf.lua", "core/map.lua",
            "core/vector.lua", "core/runtime.lua", "core/storage.lua",
            "core/itemstack.lua", "core/inventory.lua", "core/modloader.lua",
            "core/modenvironment.lua", "core/modstorage.lua",
            "core/bitops.lua", "core/pcgrandom.lua", "core/voxel.lua",
            "core/worldgen.lua", "core/particles.lua")


def build(source: Path, output: Path) -> None:
    source = source.resolve()
    for name in REQUIRED:
        if not (source / name).is_file():
            raise ValueError("missing Lua engine file: " + name)
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with ZipFile(output, "w", compression=ZIP_DEFLATED) as z:
        for file in sorted(source.rglob("*")):
            if file.is_file() and file.suffix == ".lua":
                z.write(file, file.relative_to(source).as_posix())
    with ZipFile(output) as z:
        assert all(name in z.namelist() for name in REQUIRED)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", type=Path, default=Path("lua-engine"))
    ap.add_argument("--output", type=Path, default=Path("dist/Motor-Lua-Demo.lovr"))
    args = ap.parse_args()
    build(args.source, args.output)
