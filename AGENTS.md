# Guidance for AI assistants working on this repo

The project owner is not a programmer. AI assistants write all the code, so keep it simple, readable and commented.

## Ground rules
- `docs/MASTER_DESIGN.md` is the single source of truth for the game design. Read it before making changes. Update it (including the Decisions Log) when a design decision changes, and update the roadmap status in `README.md` when a milestone is finished.
- Engine: **Godot 4.7**, GDScript with static typing (`var x: int`, `:=`).
- Use only original names, art and text. Never copy Space Rangers or No Man's Sky IP (see "Original IP Rules" in the design doc).
- Log every third-party asset and its license in `CREDITS.md`.

## Architecture
- `game/sim/` is **pure game logic** (RefCounted classes, no nodes or scenes). Examples: galaxy generation, turn rules, NPC brains, data classes with `to_dict()` / `from_dict()`. It must stay runnable on a headless server and be unit-tested.
- `game/core/` holds the autoloads:
  - `EventBus`: global signals
  - `GameState`: holds the current `GalaxyData`
  - `TurnManager`: the only place that applies orders and ends turns
  - `SaveSystem`: JSON saves
- Views (`game/space/`, `game/ui/`) **read** the simulation and send orders through `TurnManager.submit_order()`. They never change the simulation directly. This keeps multiplayer (server-authoritative) possible later.
- Content lives in data files in `game/data/*.json`, loaded through `GameData`.
- Randomness must be deterministic: seed a `RandomNumberGenerator` from the galaxy seed, the day, and an entity id. Never use the global `randf()` in `game/sim/`.
- Most scenes are built in code (see `SpaceView`, `Hud`). Keep `.tscn` files minimal.

## Commands
Replace `godot` with the path to your Godot 4.7 binary.

```bash
godot --headless --import                       # first time / after adding files (creates the class cache)
godot --headless -s res://tests/run_tests.gd    # unit tests (tests/**/test_*.gd, extend TestCase)
godot --headless -s res://tests/smoke_test.gd   # plays the game headlessly; fails on any error/warning
# Screenshots for visual review (Linux, needs xvfb):
xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-method gl_compatibility --resolution 1280x720 \
    -s res://tools/capture_screenshots.gd -- /some/output/folder
```

GitHub Actions (`.github/workflows/tests.yml`) runs the unit tests and the smoke test on every push, with common GDScript warnings treated as errors (`tests/strict_warnings.cfg` is appended to `project.godot` in CI). Keep them green. To reproduce locally, append that file to `project.godot` temporarily and don't commit the change.

## Gotchas
- When a Control is already in the scene tree, use `set_anchors_and_offsets_preset()`, not `set_anchors_preset()`. The latter keeps the old size.
- HUD buttons use `focus_mode = FOCUS_NONE` so that Space always means End Turn.
- Full-screen container Controls over the 3D view need `mouse_filter = MOUSE_FILTER_IGNORE`, or they eat the clicks meant for space.
- Commit the `.uid` and `.import` files Godot generates. `.godot/` is ignored.
- Scripts run with `-s` (tests, tools) are compiled before the autoloads exist. Don't use class names whose scripts mention autoloads (anything in `game/ui/` or `game/space/`) as types there. Use `Node` plus `call()`/`get()` instead. `game/sim/` classes are fine.
- Game balance numbers (prices, scan chances, fines, fuel prices, events) live in `game/data/goods.json`, `world.json` and `races.json`. Ship items (hulls, engines, fuel tanks, grippers, weapons) live in `game/data/equipment.json`, each race's manufacturing factors in `races.json`, and NPC loadouts and pirate numbers in `npcs.json`. Tune them there, not in code.
