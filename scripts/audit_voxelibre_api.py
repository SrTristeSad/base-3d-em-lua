#!/usr/bin/env python3
"""Static inventory of VoxeLibre's core.* / minetest.* API references.

Approximate only: not an executable compatibility test. Includes references
inside comments and strings; report identifies raw usage to guide porting.
"""
from __future__ import annotations
import argparse
import collections
from pathlib import Path
import re

CALL = re.compile(r"\b(?:core|minetest)\s*\.\s*([A-Za-z_][A-Za-z_0-9]*)\b")


def audit(game: Path, supported: set[str]) -> str:
    mods = game / "mods"
    if not mods.is_dir():
        raise ValueError("missing VoxeLibre mods/ (checkout submodules first)")
    manifests = sorted(mods.rglob("mod.conf"))
    if not manifests:
        raise ValueError("VoxeLibre has no mod.conf files")
    usage: collections.Counter[str] = collections.Counter()
    users: dict[str, set[str]] = collections.defaultdict(set)
    for path in sorted(mods.rglob("*.lua")):
        source = path.read_text(encoding="utf-8", errors="replace")
        mod = "(unknown)"
        for parent in path.parents:
            if (parent / "mod.conf").is_file():
                mod = parent.name
                break
        for name in CALL.findall(source):
            usage[name] += 1
            users[name].add(mod)
    missing = sorted(set(usage) - supported, key=lambda x: (-usage[x], x))
    available = sorted(set(usage) & supported, key=lambda x: (-usage[x], x))
    lines = [
        "# VoxeLibre API audit — static approximation", "",
        "**This report does not establish mod compatibility.**",
        "Only direct core.foo / minetest.foo references are counted;",
        "dynamic lookups are missed, and comments/strings can be counted.",
        "", f"- Mod manifests: **{len(manifests)}**",
        f"- Direct API keys referenced: **{len(usage)}**",
        f"- Referenced keys exported by Lua engine: **{len(available)}**",
        f"- Referenced keys not exported by Lua engine: **{len(missing)}**",
        "", "## Highest-frequency missing API keys", "",
        "| API key | References | Mods mentioning it |",
        "| --- | ---: | ---: |",
    ]
    for name in missing[:100]:
        lines.append(f"| {name} | {usage[name]} | {len(users[name])} |")
    lines += ["", "## Referenced and exported keys", "",
              "| API key | References | Mods mentioning it |",
              "| --- | ---: | ---: |"]
    for name in available:
        lines.append(f"| {name} | {usage[name]} | {len(users[name])} |")
    lines += ["", "## Interpretation", "",
              "An exported name may still have incomplete semantics.",
              "This report measures only API name coverage, not full gameplay.",
              "No mod files are executed or modified by this audit.", ""]
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--supported", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    supported = set(args.supported.read_text().split())
    report = audit(args.game, supported)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(report, encoding="utf-8")
    print(report.split("## Highest-frequency missing")[0])


if __name__ == "__main__":
    main()
