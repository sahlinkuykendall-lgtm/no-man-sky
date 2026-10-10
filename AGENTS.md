# Guidance for AI assistants working on this repo

- The single source of truth for the game design is `docs/MASTER_DESIGN.md`. Read it before making changes, and update it (including the Decisions Log) when a design decision changes.
- Engine: Godot 4.x, GDScript with static typing. Keep code simple, modular and commented. The project owner is not a programmer.
- Keep the galaxy simulation (`game/sim/`) as pure logic, separate from scenes, so it can run on a headless server and be unit-tested (GUT).
- Content (goods, items, races, missions, quests, recipes) is data-driven in `game/data/`.
- Use only original names, art and text. Never copy Space Rangers or No Man's Sky IP (see "Original IP Rules" in the design doc).
- Log every third-party asset and its license in `CREDITS.md`.
