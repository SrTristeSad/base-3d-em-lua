#!/usr/bin/env python3
"""Validate the JSON schema and paired indexed/linear checksums.

Performance numbers are deliberately NOT used as CI failure thresholds:
GitHub-hosted runner CPU allocation varies and FPS is measured elsewhere.
"""
import argparse
import json
import math
from pathlib import Path

CASES = {
    "radius_indexed_sparse",
    "radius_linear_sparse",
    "radius_indexed_dense",
    "radius_linear_dense",
    "physical_entity_step",
    "collision_event_search",
    "spatial_relocation",
    "node_collision_cached",
    "node_collision_uncached",
}
FIELDS = {
    "name", "entities", "iterations", "unit", "cpu_seconds_median",
    "units_per_cpu_second", "checksum", "candidates_examined_median",
}
NUMBERS = {
    "cpu_seconds_median", "units_per_cpu_second", "checksum",
    "candidates_examined_median",
}


def validate(path: Path):
    data = json.loads(path.read_text(encoding="utf-8"))
    assert data["schema_version"] == 1, (path, "schema")
    assert data["phase"] == 47, (path, "phase")
    assert data["samples"] >= 1
    assert data["clock"] == "os.clock CPU seconds"
    expected_sizes = {32, 128} if data["quick"] else {32, 128, 256}
    cases = data["cases"]
    assert len(cases) == len(CASES) * len(expected_sizes), (
        path, "missing or unexpected benchmark cases"
    )
    seen = {}
    for item in cases:
        assert set(item) == FIELDS, (path, item.get("name"), "fields")
        assert item["name"] in CASES, item
        assert item["entities"] in expected_sizes, item
        assert isinstance(item["iterations"], int) and item["iterations"] > 0
        assert item["unit"] in {"queries", "entity_steps", "event_batches", "set_pos", "geometry_queries"}
        for key in NUMBERS:
            value = item[key]
            assert isinstance(value, (int, float)) and math.isfinite(value), (
                path, item["name"], key
            )
            if key != "checksum":
                assert value >= 0
        pair = (item["name"], item["entities"])
        assert pair not in seen, (path, pair, "duplicate")
        seen[pair] = item
    assert set(seen) == {
        (name, n) for n in expected_sizes for name in CASES
    }
    for density in ("sparse", "dense"):
        for n in expected_sizes:
            a = seen[(f"radius_indexed_{density}", n)]
            b = seen[(f"radius_linear_{density}", n)]
            assert a["iterations"] == b["iterations"]
            assert a["checksum"] == b["checksum"], (
                path, density, n, "indexed query diverged from linear baseline"
            )
    for n in expected_sizes:
        a = seen[("node_collision_cached", n)]
        b = seen[("node_collision_uncached", n)]
        assert a["iterations"] == b["iterations"]
        assert a["checksum"] == b["checksum"], (
            path, n, "cached geometry differs from raw nodeboxes"
        )
    print(
        f"VALID BENCHMARK {path}: {data['runtime']}, "
        f"{data['samples']} sample(s), {len(cases)} cases"
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("files", type=Path, nargs="+")
    args = parser.parse_args()
    for report in args.files:
        validate(report)
