#!/usr/bin/env python3
"""Read-only dependency closure of an actual VoxeLibre mod.

Uses only mod.conf / depends.txt from the pinned VoxeLibre checkout. It
does not claim the Lua engine can execute the calculated prerequisites.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re

NAME = re.compile(r"^[a-zA-Z_][a-zA-Z_0-9-]*$")


def split(value: str) -> list[str]:
    return [v for v in re.split(r"[,\s]+", value.strip()) if v]


def manifests(root: Path) -> dict[str, dict]:
    result = {}
    for path in sorted(root.glob("**/mod.conf")):
        info = {}
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            if "=" in line:
                key, val = line.split("=", 1)
                info[key.strip()] = val.strip()
        name = info.get("name", "")
        if not NAME.fullmatch(name):
            raise ValueError(f"invalid mod name at {path}: {name!r}")
        if name in result:
            raise ValueError(f"duplicate mod {name}")
        required = split(info.get("depends", ""))
        optional = split(info.get("optional_depends", ""))
        legacy = path.with_name("depends.txt")
        if "depends" not in info and legacy.exists():
            for line in legacy.read_text(encoding="utf-8").splitlines():
                val = line.strip()
                if not val or val.startswith("#"):
                    continue
                if val.endswith("?"):
                    optional.append(val[:-1])
                else:
                    required.append(val)
        result[name] = {"path": str(path.parent), "required": sorted(set(required)),
                        "optional": sorted(set(optional))}
    return result


def closure(allmods: dict, start: str) -> tuple[list[str], set[str]]:
    if start not in allmods:
        raise ValueError(f"missing root module: {start}")
    visited, active, order, missing = set(), set(), [], set()

    def visit(name: str) -> None:
        if name in visited:
            return
        if name in active:
            raise ValueError(f"circular required dependency: {name}")
        if name not in allmods:
            missing.add(name)
            return
        active.add(name)
        for dep in allmods[name]["required"]:
            visit(dep)
        active.remove(name)
        visited.add(name)
        order.append(name)
    visit(start)
    return order, missing


def report(mods: dict, root: str) -> str:
    order, missing = closure(mods, root)
    direct = mods[root]["required"]
    lines = [
        f"# VoxeLibre `{root}`: real dependency chain", "",
        "Static analysis of pinned upstream mod manifests; no gameplay execution.",
        "",
        f"- Total upstream manifests: **{len(mods)}**",
        f"- Direct required dependencies: **{len(direct)}**",
        f"- Transitive required modules (including root): **{len(order)}**",
        f"- Missing dependency names: **{len(missing)}**", "",
        "## Direct dependencies", "",
        ", ".join("`" + name + "`" for name in direct) or "None", "",
        "## Ordered required dependency closure", "",
    ]
    for i, mod in enumerate(order, 1):
        lines.append(f"{i}. `{mod}`")
    lines.extend(["", "## Missing dependencies", "",
                  ", ".join(sorted(missing)) if missing else "None", "",
                  "## Interpretation", "",
                  "A dependency manifest does not demonstrate successful execution.",
                  "Do not substitute mock modules for missing APIs to claim compatibility.",
                  "Actual compatibility requires executing upstream files and validating behavior.", ""])
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--mod", default="mcl_core")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    data = manifests(args.game / "mods")
    output = report(data, args.mod)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8")
    print("\n".join(output.splitlines()[:11]))


if __name__ == "__main__":
    main()
