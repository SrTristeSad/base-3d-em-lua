#!/usr/bin/env python3
"""Start every original VoxeLibre mod under the experimental Lua engine.

This is a strict boot diagnostic, not a substitute for the playable
Luanti package. A nonzero exit code means that full-game boot is incomplete.
No VoxeLibre source file is rewritten.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def discover(game: Path) -> list[tuple[str, Path]]:
    mods = game / "mods"
    if not mods.is_dir():
        raise ValueError(f"VoxeLibre mod directory not found: {mods}")
    result: list[tuple[str, Path]] = []
    found: set[str] = set()
    for conf in sorted(mods.rglob("mod.conf")):
        text = conf.read_text(encoding="utf-8", errors="replace")
        mod_name = conf.parent.name
        for line in text.splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() == "name":
                mod_name = value.strip()
                break
        if not mod_name or any(c not in
                               "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"
                               for c in mod_name):
            raise ValueError(f"invalid mod name at {conf}: {mod_name!r}")
        path = conf.parent.resolve()
        if mod_name in found:
            raise ValueError(f"duplicate game mod: {mod_name}")
        if any(c in str(path) for c in ("\t", "\r", "\n")):
            raise ValueError(f"invalid path characters: {path}")
        found.add(mod_name)
        result.append((mod_name, path))
    if not result:
        raise ValueError(f"no mod.conf found in {mods}")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, default=Path("games/voxelibre"))
    parser.add_argument("--lua", default="lua5.4",
                        help="Lua 5.4 or LuaJIT executable")
    parser.add_argument("--fail-fast", action="store_true",
                        help="stop after first mod that cannot initialize")
    parser.add_argument("--report", type=Path,
                        help="save the full console report to a text file")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parent.parent
    game = args.game.resolve()
    mods = discover(game)
    lua = shutil.which(args.lua)
    if lua is None:
        raise ValueError(f"Lua executable not found: {args.lua}")
    with tempfile.TemporaryDirectory(prefix="voxelibre-boot-") as tmp:
        manifest = Path(tmp) / "mod-manifest.tsv"
        manifest.write_text("".join(f"{name}\t{path}\n" for name, path in mods),
                            encoding="utf-8")
        cmd = [lua, str(repo / "lua-engine" / "boot_voxelibre.lua"),
               str(manifest), str(game)]
        if args.fail_fast:
            cmd.append("fail-fast")
        done = subprocess.run(cmd, cwd=repo, capture_output=True,
                              text=True, encoding="utf-8", errors="replace")
    summary = f"VoxeLibre original mods discovered: {len(mods)}\n"
    content = summary + done.stdout + done.stderr
    sys.stdout.write(content)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(content, encoding="utf-8")
    return done.returncode


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        sys.stderr.write(f"VoxeLibre boot setup error: {error}\n")
        sys.exit(2)
