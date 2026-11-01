# Lua engine performance benchmarks — Phase 47

This directory contains a **standalone, deterministic CPU-time benchmark
harness**, not a graphical FPS test and not a pass/fail speed claim.

## Requirements

- Lua 5.4 or LuaJIT (the same runtimes already covered by API tests)
- No native dependencies, outside networks, VoxeLibre submodule, or
  additional Lua packages.
- Run commands from the **repository root** so `./lua-engine/` resolves.

## Execute

Quick smoke baseline (the same workload GitHub Actions runs):

```sh
lua5.4 benchmarks/lua_engine_perf.lua --quick --samples=2 --output=lua54.json
luajit benchmarks/lua_engine_perf.lua --quick --samples=2 --output=luajit.json
python3 scripts/check_lua_engine_benchmarks.py lua54.json luajit.json
```

More stable local measurement (default: 3 samples per case):

```sh
lua5.4 benchmarks/lua_engine_perf.lua --samples=5 --output=baseline.json
```

LuaJIT warm-up behavior may affect short runs. Run more samples and
compare **median CPU time** on the same hardware and Lua runtime.

## Workloads

| Case | Tested behavior | Unit |
| --- | --- | --- |
| `radius_indexed_sparse` | `core.get_objects_inside_radius` with objects spaced apart | queries |
| `radius_linear_sparse` | Correct linear reference scan, same positions | queries |
| `radius_indexed_dense` | Index lookup with many nearby objects | queries |
| `radius_linear_dense` | Same dense positions, full linear scan | queries |
| `physical_entity_step` | `Runtime:step(1/30)` of moving physical LuaEntities | entity-steps |
| `collision_event_search` | Indexed head-on TOI planning in sparse worlds | event batches |
| `spatial_relocation` | `ObjectRef:set_pos` with index maintenance | calls |
| `node_collision_cached` | Shared, revision-aware node collision AABB cache | geometry queries |
| `node_collision_uncached` | Same nodebox geometry via direct map and Nodebox.boxes reads | geometry queries |

All cases use explicit, reproducible positions, velocities and a
fixed query order; counts are **32, 128** in CI, plus **256** in
the default local run. `--quick` uses fewer iterations per case.
For node geometry, the runner checks cached and uncached box counts on
identical maps containing regular cubes and slabs. For radius searches,
the runner checks the indexed results against
the linear baseline by object count. The independent report
validator verifies every paired checksum at each population size.

The harness excludes object setup and forced garbage collection
from timed loops; each timed sample warms its own initial world.
Setup cost, memory footprint, Lua garbage collector pauses,
rendering, networking, chunk-generation and disk persistence
are **not measured here**. `physical_entity_step` measures real
Lua-side physics and callback work but not LÖVR rendering. It uses
a deterministic timestep, not a real-time clock.

## JSON schema

Each report includes `schema_version`, `phase`, `runtime`,
`lua_version`, `quick`, `samples`, `clock`, `notes` and
`cases`. Each case records:

- `cpu_seconds_median`: median of `os.clock()` CPU seconds.
- `units_per_cpu_second`: unit throughput (entity-steps,
  queries, event batches, or position updates).
- `checksum`: lightweight deterministic result validation;
  **not** an engine world-state hash.
- `candidates_examined_median`: internal index candidate
  count where applicable; not a duration or collision count.

GitHub Actions uploads the JSON output of both runtimes as
**Motor-Lua-Performance-Baseline** with 30-day retention.

## Interpretation

A faster indexed lookup in sparse worlds is expected, but a dense
world may provide little or no speedup. Never compare absolute
CPU times from separate, uncontrolled GitHub-hosted runners,
different hardware, different Lua builds, or environments with
different background workloads. Do not treat throughput as FPS,
and **do not fail CI on absolute benchmark times**.

The primary purpose is to identify which layer needs optimization:
radius queries, per-frame entity stepping, collision-event planning
or spatial-index updates. For future improvements, compare
identical workloads on the **same machine** before and after a
change, while preserving the Lua 5.4 / LuaJIT correctness suite.
