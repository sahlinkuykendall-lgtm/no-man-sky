# Project Ranger (working title)

A Godot 4 space game. Space is turn-based and isometric, with trading, combat and missions inspired by *Space Rangers 2*. Planets are first-person open worlds with exploration, survival and crafting inspired by *No Man's Sky*. It's planned for 8–16 player multiplayer, with a story about an invading machine race, the Ascendancy.

**Design:** [`docs/MASTER_DESIGN.md`](docs/MASTER_DESIGN.md) is the single source of truth for what the game will be.

## Status

| Milestone | State |
|---|---|
| M0: project setup, core systems, tests, CI | ✅ Done |
| M1: galaxy generation, isometric space view, turns, hyperspace jumps | ✅ Done (first playable) |
| M2: trading (markets, supply and demand, contraband, black market, fuel costs) | ✅ Done |
| M3: ships and gear | Next |

![Star system view](docs/screenshots/m2_system_view.png)
![Planet market](docs/screenshots/m2_planet_market.png)
![Galaxy map](docs/screenshots/m2_galaxy_map.png)

## How to play the current build

1. Install **Godot 4.7** (standard version, not .NET) from https://godotengine.org/download.
2. Download this repository. With GitHub Desktop: *File → Clone repository*. To get updates later, press *Fetch origin / Pull*.
3. Open Godot, click **Import**, and pick the `project.godot` file in this folder.
4. Press **F5** (or the ▶ Play button, top right) to run the game.

### Controls (space)

| Action | Control |
|---|---|
| Fly to a planet / point | Left click |
| End turn (everything moves at once) | **Space** or the *End Turn* button |
| Auto: keep ending turns until you arrive | **Shift+Space** or *Auto ▶▶* |
| Galaxy map (pick a system, set jump course) | **M** |
| Land on the planet you orbit (trade, refuel) | **L** or *Land* |
| Move camera | Right-drag, or WASD / arrow keys |
| Zoom | Mouse wheel |
| Center on your ship | **F** |
| Menu (save / load / quit) | **Esc** |

### Making money

You start with 2,500 cr and an empty 60-ton hold. Click a planet to see what's cheap there and what pays well. Fly to an inhabited one and press **L** to land. Buy goods where they're cheap (green buy price) and sell them where they pay well (green sell price). Farm worlds make food, industrial worlds make technology and minerals, and events like famines and plagues send prices soaring. Every trade moves the price, so a route stops paying if you farm it. Goods marked *BLACK MARKET* are illegal on that planet: they pay more, but police may catch you. Fuel costs money now, so keep some credits for it.

## For developers (and AI assistants)

See [`AGENTS.md`](AGENTS.md) for project layout, conventions, and how to run the tests.
