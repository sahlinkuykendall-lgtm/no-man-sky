# PROJECT RANGER — Master Design Document

> **Working title:** Project Ranger (placeholder — rename any time)
> **Engine:** Godot 4.7 · **Language:** GDScript · **Platform:** PC (Windows/Linux) first
> **Genre:** Turn-based space RPG/trader (top-down isometric) + first-person open-world planet exploration
> **Inspiration mix:** ~85% *Space Rangers 2* (core loop, turns, trade, missions, races, roles, war) · ~15% *No Man's Sky* (landing, open-world planets, survival, crafting, walkable ship)
> **Status:** Pre-production. This document is the single source of truth. Update it whenever a decision changes.

---

## Table of Contents
1. [Vision](#1-vision)
2. [Decisions Log (from the kickoff Q&A)](#2-decisions-log)
3. [Core Game Loop](#3-core-game-loop)
4. [The Galaxy Map & Space Layer](#4-the-galaxy-map--space-layer)
5. [Turn System (Solo & Multiplayer)](#5-turn-system)
6. [Space Combat](#6-space-combat)
7. [Communication, Negotiation & Hailing](#7-communication-negotiation--hailing)
8. [Hyperspace](#8-hyperspace)
9. [Ships, Equipment & Fleets](#9-ships-equipment--fleets)
10. [Trade & Economy](#10-trade--economy)
11. [Races & Governments](#11-races--governments)
12. [Roles: Rangers, Pirates, Mercenaries, Traders…](#12-roles)
13. [Player Character: Skills, Ranks, Reputation](#13-player-character)
14. [Space Stations & Bases](#14-space-stations--bases)
15. [Missions & Tasks (full catalog)](#15-missions--tasks)
16. [Text Quests & Hybrid Quests](#16-text-quests--hybrid-quests)
17. [Planetary Battles (FPS + Command + RTS)](#17-planetary-battles)
18. [Planets: Landing, Generation & Exploration](#18-planets)
19. [On-Foot Gameplay: Survival, Gear, Vehicles](#19-on-foot-gameplay)
20. [Cities](#20-cities)
21. [Crafting](#21-crafting)
22. [Walkable & Customizable Ship Interior](#22-walkable--customizable-ship-interior)
23. [The Enemy: The Ascendancy](#23-the-enemy-the-ascendancy)
24. [Story & Main Questline](#24-story--main-questline)
25. [Multiplayer](#25-multiplayer)
26. [Death, Respawn & Difficulty](#26-death-respawn--difficulty)
27. [UI / UX Overview](#27-ui--ux-overview)
28. [Art & Audio Direction](#28-art--audio-direction)
29. [Technical Architecture (Godot)](#29-technical-architecture)
30. [Development Roadmap](#30-development-roadmap)
31. [Original IP Rules](#31-original-ip-rules)
32. [Open Questions](#32-open-questions)
33. [Research Sources](#33-research-sources)

---

## 1. Vision

You are a **Ranger**: a freelance pilot in a galaxy of five rival civilizations. An ancient machine intelligence, **the Ascendancy**, has already erased life from other galaxies and has now arrived in ours, taking star systems one by one.

The galaxy is **alive without you**. Traders haul cargo, pirates raid them, militaries defend their borders, NPC rangers hunt Ascendancy ships, and the war moves forward every turn. You can join the war, get rich trading, turn pirate, run contraband for shady governments, or ignore it all and explore. The news will tell you when *"The Veyl system is under attack!"*. Whether you go is up to you.

In space, the game is a **turn-based, isometric, semi-3D** strategy RPG like *Space Rangers 2*. When you **dive into a planet's atmosphere**, it becomes a **first-person 3D open world**:
- **Inhabited worlds** have cities with jobs, shops and missions.
- **Wild worlds** have creatures, ruins, wrecks, artifacts and resources to mine, sell, or craft into upgrades for your ship.

Up to **16 players** can share one galaxy. Space turns run on a **60-second timer**, and if everyone presses Ready the turn resolves immediately.

### Design pillars
1. **A living sandbox.** NPCs and the war don't depend on the player. The coalition *can* defend the galaxy alone, but it goes better with your help.
2. **Freedom of role.** What you *do* makes you a trader, pirate, mercenary or hero. No class locks.
3. **Two scales, one world.** Strategic turn-based space, and hands-on first-person planets. Each one feeds the other: loot from planets goes into ship upgrades, and missions from space send you to the surface.
4. **Space Rangers first.** When in doubt, do what *Space Rangers 2* did. Borrow from *No Man's Sky* only for planets, survival, crafting and the ship interior.

---

## 2. Decisions Log

These answers come from the kickoff Q&A. Add new decisions at the bottom with a date.

| # | Topic | Decision |
|---|---|---|
| 1 | Title | "Project Ranger" placeholder |
| 2 | Team | Solo designer (beginner). **All code is written by AI assistants.** Choose the simplest, best-documented approaches. |
| 3 | Engine/Language | Godot 4.x + GDScript (the best-documented option, text-based, and AI assistants write it reliably) |
| 4 | Art style | Low-poly stylized (No Man's Sky-like colors) |
| 5 | Platform | PC first (Windows/Linux) |
| 6 | Players per world | 8–16 |
| 7 | Hosting | Both: a player can host, and dedicated servers are supported (headless Godot export) |
| 8 | Solo | Fully playable solo/offline; no turn timer in solo |
| 9 | PvP | Host chooses Co-op or PvP when creating a game. Both modes let you hire NPC wingmen/mercenaries. |
| 10 | Planet time | **The galaxy keeps advancing** every 60s while you're on a planet. Planet time feels normal (real-time), and your ship is docked/safe. |
| 11 | Space turns | Exactly like SR2: give orders → End Turn → everything moves at once |
| 12 | Space combat | Exactly like SR2 (turn-based, ranges, part damage, wear) |
| 13 | Map | One galaxy, SR2-style (~60 star systems in sectors, linked by hyperspace) |
| 14 | Hyperspace | Keep arcade battles, redesigned as **"Rift Runs"** (see §8) |
| 15 | Text quests | Yes, plus **hybrid quests** that switch between text and 3D in either direction, as well as pure text and pure 3D quests |
| 16 | Planet battles | All three: first-person, first-person while commanding allies, and the RTS command view |
| 17 | Planet size | Large landing **zones** first, full walkable **spheres** later |
| 18 | Landing | Short cinematic atmospheric entry while the world loads |
| 19 | Survival | Full survival (oxygen, hazards, life support, health, stamina) |
| 20 | Planet travel | Walk/jetpack, rover, fly ship low and land anywhere, and the ship interior is walkable and customizable |
| 21 | Wild finds | All: minerals/resources, artifacts, crashed ships/ruins, creatures |
| 22 | On-foot gear | Multi-tool (mining/scanning/basic weapon) **plus** separate guns, and an upgradable suit |
| 23 | Crafting | Everything except base-building. Instead, you can **buy or rent property in cities.** |
| 24 | Ship equipment | SR2 system plus extras |
| 25 | Ships owned | Fleet: own several ships flown by hired NPC pilots |
| 26 | Trade | SR2 system plus selling found and crafted goods |
| 27 | Races | 5 original races that fill SR2's roles, with new names and lore |
| 28 | Playable races | Any of the 5 |
| 29 | Story | Dynamic sandbox invasion **plus** an optional main questline |
| 30 | Enemy lore | Drafted in this doc (§23); the user will edit it |
| 31 | Roles | Emergent from actions and reputation, like SR2 |
| 32 | Skills | The 6 SR2-style skills plus on-foot skills |
| 33 | Death | Respawn with a penalty (the host can enable Hardcore) |
| 34 | Dislikes to avoid | None stated |
| 35 | Engine version (2026-10-10) | Godot **4.7** (latest stable when development started) |
| 36 | Testing (2026-10-10) | A small built-in test runner (`tests/run_tests.gd`) plus a headless smoke test that plays the game. This replaces the GUT plugin to avoid an external dependency |
| 37 | Hyperspace departure (2026-10-10) | As in SR2, ships must fly out to the system's **hyperspace boundary** (dashed purple ring) before jumping. Fuel = 1 per parsec, and transit takes 1 day per 8 pc |
| 38 | Market prices (M2) | Price = base × economy × tech level × government × race × a small fixed per-planet quirk × event × supply. Supply: fewer units in stock means a higher price. Each market buys 5% below and sells 5% above its middle price, so buying and selling straight back always loses money. Stock drifts back to normal by 8% of the gap per day. Numbers live in `game/data/goods.json`, `world.json` and `races.json` |
| 39 | Contraband & black market (M2) | Illegal goods (by government, §11, plus race bans) can still be traded on the planet's **black market**: 40% pricier, less stock, and each deal risks a sting (fine + confiscation). Police scan ships that arrive at a planet with cargo (chance by government) and confiscate contraband with a fine. Anarchies scan nothing. Wanted status and karma come later (M5–M7) |
| 40 | Lumari ban alcohol (M2) | Gives §10's "Alcohol: illegal on some worlds" a home: it's illegal on every Lumari world |
| 41 | Starting money & fuel (M2) | Start with **2,500 cr** and a **60-ton** hold (about 62 t since M4, see #57). Fuel now costs money (9–14 cr/unit by government). A pilot who can't afford fuel gets free emergency fuel up to 14 units (enough to reach a neighbouring system) from the Ranger Corps, so nobody is ever stranded. NPC ships still refuel free until M5 gives them real trading |
| 42 | Trading takes no time (M2) | Landing (L) on an inhabited planet you orbit opens its market. Trading is instant and costs no turn, like SR2. Credits live on the player's ship until pilots/characters are their own data (M15) |
| 43 | Ship = hull + equipment (M3) | A ship is built from a **hull** plus one item per equipment slot. M3 has the hull, **engine** and **fuel tank**. Weapons (M4), radar, scanner, gripper, repair droid and shield (M4–M5) plug into the same system later. The ship's stats come from its items: speed, jump range and hyperspace speed from the engine, fuel capacity from the tank, armor (max hull HP) from the hull. Models and numbers live in `game/data/equipment.json` |
| 44 | Weight vs cargo (M3) | Like SR2, a hull's **size** is shared between equipment and cargo: cargo space = hull size − weight of everything installed. Better engines are heavier, so you trade hold space for speed. A purchase is refused if the new cargo space would be smaller than what you carry |
| 45 | Race of manufacture (M3) | Every shipyard sells only its own race's models, up to the planet's tech level. Each race changes price, weight, wear and armor (`races.json` → `manufacturing`): Veyari gear is pricey, light and long-lasting; Lumari gear is light; Skarn gear is cheap but wears fast; Gorruk hulls are tough but heavy; Human gear is the baseline. The player starts with a Courier hull, Spark Drive and Standard Tank built by their own race (a human pilot has speed 170, jump 20 pc, fuel 30 and a 60 t hold; since M4 also a Basic Gripper and a Pulse Laser, with a 62 t hold) |
| 46 | Wear (M3) | Engines wear a little every day of flying and more on each hyperspace jump. Fuel tanks wear on jumps. Above 50% condition an item works at full power; below 50% it loses power, down to **half power at 0%**. It never breaks completely in M3. The hull's condition is its HP (damage arrives with combat in M4). The player gets a warning when an item drops below 50% |
| 47 | Shipyard prices (M3) | Buying a new item **trades in** the old one for up to 60% of its price (40% of that is kept even when worn out). Repairing an item from 0% to 100% costs 35% of its price; hull repairs cost 8 cr per HP (3 cr since M4, see #57) (times the maker's price factor). A pilot who can't afford a full repair pays for what they can, and the Ranger Corps patches the engine and tank up to 50% for free, so nobody is stranded |
| 48 | Hyperspace speed (M3) | Replaces the fixed "1 day per 8 pc" from Decision #37: transit speed now comes from the engine (8–14 pc/day) |
| 49 | Weapons (M4) | Three types. **Energy** (lasers, beams): mid range, no ammo. **Fragment** (cannons): short range, and each shot also hits the target's allies within its splash radius for half damage. **Missiles**: longest range and hardest hits, but limited ammo, reloaded by *Repair*. Each weapon has a damage range (min–max), a range, a weight, and wears a little with every shot. A hull's **weapon slots** limit how many you carry. A new weapon goes into a free slot (no trade-in), and you sell weapons for their trade-in value. 10 weapons, tech 1–8, live in `equipment.json` |
| 50 | Combat turns (M4) | Each ship has one target (a ship or an asteroid). After *Attack*, your ship chases the target until it is within 80% of its shortest weapon range, then holds there. After everyone has moved, every weapon in range fires once per day, and all ships fire at the same moment (a ship destroyed this turn still gets its last shots off). Damage is a random roll between min and max, seeded so it's the same on every computer. Skills (Accuracy vs Maneuverability), shields, per-weapon targets and shooting down missiles come later |
| 51 | Safe orbits (M4) | Ships in orbit of an **inhabited planet** are protected by its defenses: they can't shoot or be shot. Traders under fire flee there, and so can you |
| 52 | Death = rescue (M4) | First version of #33. When your hull reaches 0, the Ranger Corps tows the wreck to the nearest inhabited planet (in the same system if there is one, otherwise your race's home system). It costs **20% of your credits**, your cargo is left in a container where you were destroyed, and the hull is patched to 30%. Hardcore mode comes later |
| 53 | Pirates & danger (M4) | Pirates come in three loadouts (Raider, Marauder, Warlord) in `game/data/npcs.json`. Each system has a normal number of pirates. Race home systems have none, and the farther a system is from every home system, the more and tougher its pirates (danger = distance to the nearest home ÷ 30 pc). Pirates hunt any non-pirate ship within 500 units that isn't in a safe orbit, and give up beyond 900. Destroyed pirates and traders are slowly replaced (4% chance per day per system); new pirates arrive at the hyperspace boundary |
| 54 | Bounties, and no attacking traders yet (M4) | The Ranger Corps pays a **bounty** for every pirate the player helps destroy (350 / 900 / 2,200 cr). The player can't attack peaceful ships yet. Piracy as a player choice comes with karma and police in M5 |
| 55 | Loot & gripper (M4) | Destroyed ships leave a **cargo container** with 40–80% of their cargo plus **Salvage** (a new good: scrap that industrial worlds pay well for). Containers drift away after 20 days. The **gripper** is a new equipment slot (every pilot starts with a Basic Gripper). At the end of each turn it picks up every container within its range, as far as the hold allows |
| 56 | Asteroids (M4) | About 45% of systems have an asteroid belt beyond the last planet. Shoot a rock to break it into minerals (pick them up with the gripper). Broken rocks are replaced after 20–40 days |
| 57 | Combat rebalance (M4) | The Courier grows to 90 t so the new starting gripper and laser still leave a human pilot a 62 t hold. Hull armor is raised (Courier 100 … Gunship 480). Hull repair drops to **3 cr per HP** (replaces the 8 cr in #47) because hulls now take damage often. Police scans only check the player for now (NPC traders carry nothing illegal) |
| 58 | Save version 4 (M4) | Old saves are upgraded: the player gets a gripper and a Pulse Laser, systems get asteroid belts, and the NPC traders are replaced by new, equipped traders and pirates |

---

## 3. Core Game Loop

```
            ┌────────────── SPACE (turn-based, isometric) ──────────────┐
            │  Trade • Fight • Hail/negotiate • Take missions • Mine    │
            │  asteroids • Defend/liberate systems • Hire wingmen       │
            └───────┬───────────────────────────────▲──────────────────┘
       dive into    │                               │  launch to orbit
       atmosphere   ▼                               │
            ┌────────────── PLANET (first-person, real-time) ───────────┐
            │  CITY: shops, gov offices, bars, jobs, text quests,       │
            │        rent/buy property, black market                    │
            │  WILDS: explore, mine, scan creatures, loot wrecks/ruins, │
            │        find artifacts, survive hazards, ground battles    │
            └───────────────────────────────────────────────────────────┘
                     │ loot/materials → craft/sell → better ship/gear ┘
```

**Short loop (minutes):** buy cheap goods → fly → sell high, or land → explore → loot → sell or craft.
**Mid loop (hours):** take government missions → earn money and reputation → upgrade the ship → fight stronger enemies.
**Long loop (campaign):** the Ascendancy war moves system by system. Liberate systems, raise your rank, follow the main questline, and stop the three Ascendancy Primes.

---

## 4. The Galaxy Map & Space Layer

### Structure (SR2-style)
- **One galaxy** of about **60 star systems** (configurable: 40 small, 60 normal, 80 large), grouped into **sectors**.
- Each system has a **star**, **0–6 planets** (inhabited or wild), **asteroid fields**, and possibly **stations** (§14).
- Systems are linked by **hyperspace jumps**. Jump range depends on the engine, and fuel is used per parsec.
- The galaxy is **procedurally generated from a seed** at new game. Each race starts with a home region, and the Ascendancy enters from one edge (or several, on hard difficulty).

### View
- **Isometric top-down, semi-3D.** 3D models (low-poly ships, planets, stars, asteroids) seen through a tilted orthographic camera, like SR2's look but rendered in real 3D.
- Planets visibly orbit the star. Each turn they move along their orbits, so travel times change, as in SR2.
- Zoom levels: **System view** (the main gameplay view) ↔ **Galaxy map** (the strategic overview: who controls which system, where battles are, news markers).

### Galaxy map shows
- Systems colored by controlling race, or by Ascendancy faction once captured.
- ⚠ **"Under attack"** markers and ⚔ **"Liberation underway"** markers.
- Known prices (if you've visited or bought data), your mission markers, and your fleet.
- A news ticker: *Galactic News Network*, which reports attacks, liberations, price events (famine, plague, harvest), pirate activity, and ranger rankings.

---

## 5. Turn System

### The turn
- **1 turn = 1 galactic day.**
- **Planning phase:** set your ship's destination or movement, pick weapon targets, use items, open dialogs, trade on planets.
- **Resolve phase:** every ship in the system (players and NPCs) moves and fires at once, in a short animation (about 2–4 seconds, speed adjustable).

### Solo
- No timer. Press **End Turn** (or hold it to auto-advance several days until something happens, like SR2's "fly until arrival").
- **Planet clock (option):** by default the galaxy is **paused** while you're on a planet in solo. One landing costs 1 day. Option: "Real-time planet clock", where 1 day passes every 60 seconds on the surface, as in multiplayer.

### Multiplayer
- **60-second planning timer** (the host can set 30–120s).
- A **Ready** button. When **every active human player is Ready, the turn resolves immediately**.
- **Auto-ready** applies to players who are:
  - **On a planet** (first person). Their ship is docked and safe, and the galaxy keeps advancing around them (Decision #10).
  - Inside a **text quest** screen (the quest may cost several days; see §16).
  - In **hyperspace transit** (they play their Rift Run while turns tick; see §8).
  - AFK or disconnected (their ship holds position, or keeps following its autopilot route).
- **Alerts reach players on planets.** If the system you're in comes under attack, you get an in-world alert ("Ascendancy forces entering system!"). You can launch, or stay and help defend the city if they invade (§17).
- Autopilot orders (fly to X, follow ship Y, patrol) let you leave your ship flying while you're busy.

---

## 6. Space Combat

**Same as SR2:** it happens in the same turn-based world as everything else. There's no separate battle screen. Everyone in the system keeps acting while you fight.

- **Movement:** choose a destination for the turn. Engine speed sets how far you get.
- **Weapons:** each weapon has a **range**, **damage**, **type** and **wear**. Assign a target per weapon (or auto-target). Shots fire during the resolve animation.
- **Weapon types** (original names TBD):
  - **Energy:** lasers and beams. Hitscan, accurate, no ammo.
  - **Fragment:** cannons and shrapnel. Area damage, good against swarms.
  - **Missiles/torpedoes:** limited ammo, homing, can be **shot down** by point-targeting them.
- **Hit math:** your **Accuracy** skill against the target's **Maneuverability** sets the damage dealt, from min to max. The target's shield generator reduces damage by a %.
- **Damage:** the hull takes damage, and equipment takes **wear** from combat and use. Broken gear works badly or stops working.
- **Loot:** destroyed ships drop cargo, equipment and (Ascendancy) **cores**, which you collect with the **gripper**.
- **Asteroids:** shoot them for ore and pick it up with the gripper.
- **Fleeing:** jump to hyperspace (you must be clear of the planet's gravity well), or land on a planet (enemies can't follow; hostile planets may refuse you).
- **Combat items:** drugs and stims (temporary skill boosts), combat software and hacks (§9), and repair kits.

### How the prototype works (Milestone 4)
- **Attacking:** click a pirate (red ship with a name) or an asteroid, then press **Attack (T)** in the info panel. Your ship chases the target and fires every turn it is in range. The dashed red circle shows your longest weapon range, and the red ring marks your target. *Cease fire (T)* stops. You can still fly anywhere; a new course stops the chase.
- **Each turn:** ships move, then all weapons in range fire at once (Decision #50). The turn animation shows beams, bullets and missiles, floating damage numbers and explosions. The log adds up the damage you dealt and took.
- **Weapons:** Decision #49. Buy and sell them in the Shipyard tab. Missiles show their ammo in the *Your ship* panel.
- **Pirates:** Decision #53. A pirate that spots you sends a warning ("…is coming for you!"), and Auto stops. Flee to an inhabited planet (safe orbit, Decision #51) or fight. Bounties: Decision #54.
- **Loot and asteroids:** Decisions #55 and #56. Click a container to fly to it; the gripper picks it up when you're close.
- **Losing:** Decision #52.
- **NPC traders** now carry real equipment and cargo, flee to the nearest inhabited planet when shot, and leave wrecks with their cargo. They still don't really trade (M5).
- **Not yet:** shields, radar, scanner, repair droids, skills, police and rangers fighting pirates, NPCs travelling between systems, hailing (all M5), and Ascendancy cores (M6).

---

## 7. Communication, Negotiation & Hailing

You can **hail any ship, planet or station** in the system, like SR2's comms. What you can do depends on your **relations**, their **race personality**, your **Charisma**, and the **power balance** between you.

### Hailing a ship — options
| Option | What happens |
|---|---|
| **Talk / ask news** | Rumors: prices, pirate sightings, Ascendancy movements, quest hints |
| **Ask for help** | Ask them to join you against a target. They agree based on relations, their role, and the target |
| **Propose joint attack** | Recruit them to attack an Ascendancy or pirate ship together |
| **Hire** | Mercenaries and rangers join your fleet for pay (limited by your Leadership skill; §9) |
| **Demand cargo / money** | A pirate move. If they're weaker and afraid, they pay or drop cargo. Damages relations and karma |
| **Demand surrender** | Their ship stops and drops cargo, or fights back |
| **Offer bribe** | Pay police or pirates to leave you alone |
| **Threaten** | A Charisma and power check. May scare them off, or make them hostile |
| **Surrender / plead** | Drop cargo to stop being attacked |
| **Trade** (special NPCs) | Wandering merchants sell rare items |

### Hailing a planet or station
- Request landing (denied if relations are terrible, or you're wanted).
- Pay off fines / bounty on your head.
- Ask for military support, if you are high-ranked with them.
- Report a crime or pirate location (bounty).

### Personality matrix (examples)
- **Veyari** rarely accept threats; they respond to diplomacy.
- **Gorruk** respect strength and may accept a duel challenge; they despise begging.
- **Skarn** accept bribes easily, and might sell you out.

---

## 8. Hyperspace

When you jump between systems you enter **hyperspace**, a transit that takes **several turns** depending on distance and engine.

### Rift Runs (our version of SR2's arcade battles)
- During transit, your ship may hit **rift encounters**: short **real-time arcade segments** (third-person, WASD + mouse) in a swirling rift tunnel.
- **Encounter types:**
  - **Riftborn ambush.** Strange native creatures of the rift (a non-playable hostile species, like SR2's Klissans) attack. Survive or kill them for **rift crystals** (a valuable crafting material).
  - **Ascendancy interceptors.** Dominator-like patrols pull your ship out of the jump.
  - **Pirate interdiction.** Pirates rip you out of the jump.
  - **Rift anomaly.** Optional: fly through it for loot, a shortcut, or a risky event.
- **The ship you fly is your real ship.** Equipment matters, and damage stays with you.
- **Skippable:** "Auto-resolve" uses a stat-based simulation with a worse outcome than playing it yourself. Good for multiplayer and for players who dislike arcade.
- **In multiplayer:** you're auto-ready while in transit. The galaxy keeps ticking and the Rift Run plays in real time for you.

---

## 9. Ships, Equipment & Fleets

### Hull
- Hulls vary by **race of manufacture**, **size** (the total weight/space for equipment and cargo), **armor**, **weapon slots (1–5)** and **equipment slots**. Big hulls may lose slots, as in SR2.
- **Ship classes** per race (about 5 each): Courier, Trader, Fighter, Heavy Fighter, Corsair/Gunship. Plus special hulls from research, artifacts and quests.

### Equipment slots (SR2 core)
| Slot | Function |
|---|---|
| **Engine** | Speed per turn + hyperspace jump range |
| **Fuel tank** | Fuel capacity = how far you can jump before refueling |
| **Radar** | Detection range in the system |
| **Scanner** | See the contents and equipment of other ships (blocked by strong shields) |
| **Repair droid** | Repairs the hull each turn |
| **Gripper** | Picks up cargo, ore and loot. Has a mass limit |
| **Shield generator** | Reduces incoming damage by a % |
| **Weapons ×1–5** | See §6 |

Each item has: **tech level (1–8)**, **manufacturer race** (affects price, quality and repair cost), **size/weight**, **wear %**, and **upgrade sockets**.

### Extras (our additions)
- **Tuning modules** (SR2's micromodules): small chips that tweak a stat (+speed, −weight, +range, auto-repair). Socketed into items. Craftable (§21).
- **Artifacts:** rare items found on planets, in wrecks, from quests, or dropped by Ascendancy bosses. They're powerful passive bonuses (no wear, a hull bonus, an auto-targeting AI, antigrav to reduce weight…). Limited artifact slots.
- **Probe bay:** launch probes to survey wild planets from orbit (SR2-style), which reveals resource and artifact hotspots before you land.
- **Rover hangar:** carries your planetary rover.
- **Cargo pods / smuggling compartments:** hidden cargo that police scans miss more often.
- **Cosmetics:** paint, decals, engine trail color.
- **Interior modules:** see §22.

### Wear & repair
- Items wear with use and with damage. Repair them at planets and stations; the cost depends on the item's race and your **Technical** skill.

### How the prototype works (Milestone 3)
- **Items built so far:** 6 hulls (Courier, Freighter, Fighter, Heavy Fighter, Bulk Hauler, Gunship; tech 1–7), 6 engines (Spark to Zenith Drive; tech 1–8) and 5 fuel tanks (Standard to Voidrunner; tech 1–8). Each comes in five versions, one per race (Decision #45). Weapon slots are listed on hulls but do nothing until M4.
- **Shipyard:** every inhabited planet has one. **Land (L)** and open the **Shipyard** tab. It shows your ship (cargo space, hull HP, each item with its condition) with a *Repair all* button, and everything for sale with its stats, weight, price and what you would pay after the trade-in.
- **Rules:** Decisions #43–#48. (Since M4, NPC ships are built from the same hulls and equipment.)
- **Not yet:** the Technical skill (repair discounts), tuning modules, artifacts, buying extra ships and fleets. These come with their own milestones.

### Fleets & wingmen
- **Leadership skill** sets how many ships can follow you (1–5, plus perks for larger fleets).
- **Hire mercenaries** (they bring their own ship and take a cut or a wage), or **buy extra ships** and hire **NPC pilots** to fly them.
- **Orders:** Follow · Attack my target · Defend me · Hold position · Go to · Trade route (automated trading between two planets: your passive income) · Return to base.
- Pilots have **skills and loyalty**. Unpaid or mistreated pilots leave, or turn pirate.
- In multiplayer, other players' fleets count toward the system's simulation load. The server caps total fleet ships (host setting).

---

## 10. Trade & Economy

### Goods (SR2-style base list)
| Good | Notes |
|---|---|
| Food | Cheapest on agricultural worlds |
| Medicine | Prices spike during plague events |
| Alcohol | Illegal on some worlds |
| Minerals | Also mined from asteroids or planets |
| Luxuries | Rich democracies pay well |
| Technology | Industrial worlds produce it |
| Weapons | **Contraband** on some worlds |
| Narcotics | **Contraband** almost everywhere. Huge profit, big karma and relations hit |

### Our additions
| Good | Source |
|---|---|
| **Exotic materials** | Mined or harvested on wild planets (rare ores, gases, plants) |
| **Xeno-specimens** | Creature scans and samples (sold to research stations) |
| **Salvage** | Parts from wrecks on planets |
| **Relics** | Ancient ruins loot (collectors and museums) |
| **Crafted goods** | Things you make (§21) and sell |
| **Ascendancy cores** | Dropped by destroyed Ascendancy ships. Traded at Ranger Hubs for gear (like SR2's nodes) |

### Prices
- Each planet has an **economy type**: **Agricultural / Industrial / Mixed**. Each has a **tech level** and a **government** (§11).
- **Supply and demand:** selling floods the market and drops the price, and it recovers over days. Profitable routes fade if you farm them.
- **Events** move prices: famine, plague, harvest, war, an Ascendancy attack nearby, a trade embargo.
- **Information:** the Galactic News Network, NPC chat, paid market data at Trade Exchanges, and a galaxy search in the planet terminal ("where is X sold cheapest?" for a fee).

### Contraband & law
- Legality depends on the **government type**.
- **Police scans** happen on approach or landing. Getting caught means a **fine**, confiscation, lost relations, or being refused landing, and repeat offenders become **wanted** (bounty).
- The **black market** (in city back alleys or at Pirate Havens) buys and sells contraband and stolen goods.

### Money
- **Credits (cr)**. Sinks: equipment, repairs, fuel, rent and property, hiring, fines, bribes, investments in stations (§14).

### How the prototype works (Milestone 2)
- **Goods built so far:** the 8 base goods, plus Salvage from wrecks (M4). The other additions above arrive with the systems that produce them (planets M8–M9, the Ascendancy M6).
- **Markets:** every inhabited planet has one. Open it with **Land (L)** while in orbit. The market screen shows each good's typical price, the buy and sell price (green = a good deal), the market's stock and your hold.
- **Prices** follow Decision #38. Producers (farm worlds for food and alcohol, industrial worlds for minerals, medicine, technology and weapons) sell cheaply. High-tech worlds sell technology, medicine and weapons for less. Rich democracies pay more for luxuries. Races have tastes (for example, the Gorruk make cheap weapons and pay a lot for alcohol). Prices move as you trade, so a route fades if you farm it, and recovers over a week or two.
- **Market events:** famine, plague, bumper harvest, border war, miners' strike, tech boom and grand festival. Each lasts 5–20 days. The news reaches you if it happens within 40 pc. The planet info panel shows what is cheap, what pays well and what is illegal.
- **Contraband, police and the black market:** Decision #39.
- **Fuel:** Decision #41.

---

## 11. Races & Governments

Five **original** races fill the same roles as SR2's five. All five are playable. Your race affects starting relations, prices, starting ship, and how NPCs treat you.

| Race | SR2 role it fills | Personality | Strengths | Relations |
|---|---|---|---|---|
| **Humans** | Humans | Adaptable traders and diplomats, wildly varied individuals | Trade, versatile mid-tech | Good with Veyari and Lumari; unstable with Skarn and Gorruk |
| **Veyari** | Gaalians | Ancient, serene, genetically perfected; value peace and knowledge | Best tech (expensive, lowest wear) | Friendly to all; often targeted by others |
| **Lumari** | Faeyans | Brilliant scientists, physically frail, allied with the Veyari | Research, scanners, science bases | Close to Veyari; frequent victims of Skarn espionage |
| **Skarn** | Pelengs | Cunning, greedy, love schemes and dark humor; work for whoever pays | Smuggling, cheap gear, black markets, bribery | Distrusted by most; useful to all |
| **Gorruk** | Maloqs | Massive warrior culture; honor and glory; despise "weak" science | Tough hulls, heavy weapons (older tech) | Respect strength; hostile to Lumari intellectualism |

> Art and lore for each race need concept passes. Names are placeholders the user can change.

### Non-playable factions
- **The Ascendancy** (three warring sub-factions; §23).
- **Pirate Clans:** several named clans with their own havens. Individual clans can become allies if your karma is low enough.
- **The Riftborn:** hostile life native to hyperspace (§8).

### Government types (affect laws, missions and prices)
| Government | Contraband | Missions favored | Notes |
|---|---|---|---|
| **Anarchy** | Nothing illegal | Smuggling, hits | Pirates welcome, lawless |
| **Dictatorship** | Weapons and narcotics illegal | Military and assassination | Harsh police, high fines |
| **Monarchy** | Narcotics illegal | Escort (nobles), delivery | Honor-based, likes rank |
| **Republic** | Narcotics illegal | Balanced | Standard |
| **Democracy** | Narcotics and weapons illegal | Protection, diplomacy, science | Richest, pays most for luxuries |

**Race mission tendencies** (from SR2): Gorruk lean toward elimination and military missions; Lumari toward science, recon and delivery; Skarn toward smuggling, espionage and sabotage; Veyari toward protection and diplomacy; Humans toward trade and balanced missions.

Relations are tracked **per race** and **per planet**. Quest outcomes can shift them. A mission might secretly insult another race, and aliens might lie to you (as in SR2).

---

## 12. Roles

**Your role emerges from what you do** (Decision #31).

### Starting background (just a starting kit, not a class)
At character creation you pick a **race** and a **background**. It sets your starting ship, gear, money and relations, and nothing locks you into it.

| Background | Start |
|---|---|
| **Warrior** | Combat-oriented ship, good weapons, low money |
| **Mercenary** | Balanced combat ship, decent money, neutral relations |
| **Trader** | Big cargo hold, weak weapons, more money, good relations |
| **Corsair** | Fast, maneuverable, good weapons, some bad relations |
| **Pirate** | Fast, armed, bad karma, welcome at pirate havens, wanted in some systems |

### NPC roles in the living galaxy (and roles you can drift into)
| Role | Behavior |
|---|---|
| **Rangers** | Independent heroes like you. They fight the Ascendancy, hunt pirates, trade and take missions. There's a **public ranking leaderboard** where NPC and player rangers compete |
| **Traders / Transports** | Haul goods between planets. Pirate targets |
| **Liners** | Passenger ships. Escort and assassination targets |
| **Diplomats** | Fast VIP ships. Escort and assassination targets |
| **Warships** | Government military. Defend systems, join liberations, police |
| **Pirates** | Prey on traders, extort, smuggle, raid |
| **Mercenaries** | Hire-for-pay fighters |
| **Smugglers** | Run contraband past police |

### Karma / reputation drives your "role"
- **Karma** (hidden-ish, shown as a reputation descriptor) goes down when you attack innocents, extort, smuggle or break deals.
- Low karma makes police hostile, gets you turned away from landings and puts bounties on you, but pirates welcome you. High karma brings better government missions and more trust.
- **Titles** appear on your profile based on what you do: "Notorious Pirate", "Merchant Prince", "Ascendancy Hunter", "Mercenary for Hire"…

---

## 13. Player Character

### Ship / space skills (SR2's six)
| Skill | Effect |
|---|---|
| **Accuracy** | More damage with ship weapons (relative to target maneuverability) |
| **Maneuverability** | Less damage taken in space |
| **Technical** | Lower wear and repair cost, more probes, smaller equipment size |
| **Trading** | Better buy and sell prices |
| **Charisma** | Better NPC reactions, quest rewards, negotiation |
| **Leadership** | More wingmen and fleet ships |

### On-foot skills (our additions)
| Skill | Effect |
|---|---|
| **Marksmanship** | First-person gun accuracy, recoil and damage |
| **Survival** | Hazard resistance, slower oxygen and life-support drain |
| **Prospecting** | Mining yield, better scanner detail on resources and creatures |
| **Engineering** | Crafting quality, more recipe slots, vehicle repair |
| **Hacking** | Bypass locked doors, terminals and Ascendancy machines; city side-jobs |
| **Athletics** | Stamina, jetpack fuel, sprint |

- **XP** comes from kills, missions, liberations, discoveries, crafting and quests. You **spend points** on skills (as in SR2).
- **Equipment, implants and stims** give temporary or permanent boosts.

### Ranks & medals
- **Ranger rank** rises through Ranger Hub missions, killing Ascendancy ships, and liberating systems.
- **Military rank** (per race government) rises through military missions and investing in military bases. Higher ranks unlock military support, better missions and restricted gear.
- **Medals** for big deeds: system liberations, boss kills, hard missions.

---

## 14. Space Stations & Bases

Stations orbit within systems. The Ascendancy can **destroy** them, and players can **fund** building new ones (as in SR2).

| Station | Services |
|---|---|
| **Ranger Hub** | Ranger missions, trade **Ascendancy cores** for special gear and tuning modules, ranger rankings, info terminal |
| **Military Base** | Military missions and ranks, buy military gear (rank-locked), **request strikes** (fund a military attack on an Ascendancy system) |
| **Research Station** | Upgrade equipment, sell probes, buy research on new tech (funding speeds up galaxy-wide tech progress), sell xeno-specimens |
| **Trade Exchange** | Market data, galaxy price search, trade contracts, insurance |
| **Medical Station** | Heal, cure diseases, buy implants, stims, skill respec |
| **Pirate Haven** | Black market, change your ship's registration (citizenship), pirate missions, fence stolen goods |

**Investing:** donate credits toward building or upgrading a station. Rewards are rank, relations and discounts.

---

## 15. Missions & Tasks

### How missions are offered (SR2 flow)
1. Land on a planet → open the **Government Office** (in the city as a real 3D building with an NPC official, *or* through a quick menu terminal).
2. The official offers **1 mission** (better relations show more options). You can **negotiate difficulty**: **Easy / Normal / Hard**. Harder means **more pay and less time**, and sometimes a bonus like a **medal, tuning module or artifact**.
3. Accept → it goes into the **Mission Log** with a **deadline in days**. Map markers appear.
4. Complete it → return to the issuer (or a specified planet) to collect. **Failure** (timeout, target escaped, escorted ship died) means a relations penalty.
5. You may hold **1 government mission at a time** (as in SR2), plus any number of side and city tasks.

**Example mission offer (what it looks like):**
```
┌─ Government of Kessa Prime (Republic · Human) ──────────────┐
│ "Ranger, a Skarn smuggler named Vrel Tosk has been running   │
│  narcotics through our system. Find him and destroy his ship.│
│  He was last seen heading toward the Ordu system."           │
│                                                              │
│  Reward: 18,400 cr        Deadline: 22 days                  │
│  Difficulty:  [ Easy ]  [■Normal■]  [ Hard ]                 │
│  (Hard: 31,000 cr · 14 days · +Tuning module)                │
│                                                              │
│            [ Accept ]   [ Decline ]   [ Ask for details ]    │
└──────────────────────────────────────────────────────────────┘
```

### A. Space missions (SR2 core types)
| Type | Objective | Fail if | Notes |
|---|---|---|---|
| **Delivery** | Carry cargo or a special package to planet X | Late, or package lost | Most varied flavor text: odd cargo, live creatures, VIP passengers |
| **Assassination / Bounty** | Destroy a named ship (pirate, criminal, enemy diplomat) | Target escapes past the deadline | Targets run to planets or bases; you need speed |
| **Escort** | Keep a liner, diplomat or transport alive for N days or until it arrives | Escort destroyed (even after the goal, before payout) | Diplomats are fast, so your engine must keep up |
| **System protection** | Protect all civilian ships in a system for N days | Too many civilians lost | The easiest early mission |
| **Recon / Survey** | Probe or scan planets, scan a specific ship, chart an anomaly | Late | Lumari favorite |
| **Smuggling** | Deliver contraband past police | Caught or late | Skarn and pirate givers. Karma hit |
| **Espionage** | Scan a rival race's military ship, or deliver stolen data | Caught | Hurts relations with the target race if discovered |
| **Liberation support** | Join the attack on an Ascendancy-held system and destroy N ships | System not freed in time | Big rank and XP |
| **Defense call** | Reach a system under attack and defend it for N days | System falls | Comes as an emergency broadcast |

### B. Planet-surface missions (our first-person additions)
| Type | Objective |
|---|---|
| **Ground defense** | Ascendancy drop-ships land near a city. Fight them off (FPS), with or without allied troops (§17) |
| **Liberation assault** | After a system is freed from orbit, retake the planet's factories (FPS, command or RTS; §17) |
| **Retrieval** | Recover a black box, crashed courier or lost probe in the wilderness. Hazards, creatures, maybe pirates |
| **Rescue** | Find and escort stranded survivors back to the city or your ship |
| **Bounty on foot** | Track a fugitive hiding in a city district or a wilderness camp |
| **Sabotage** | Infiltrate a pirate or rival-race facility and plant a device (Hacking helps) |
| **Survey** | Scan N species, sample N minerals, map a ruin |
| **Clear the nest** | Exterminate a dangerous creature nest threatening a settlement |
| **Base raid** | Assault a pirate base (inspired by SR2's pirate-base quests): go in quietly, destroy it, capture the leader alive for a bonus |

### C. City tasks (small jobs)
Short tasks from city NPCs and job boards: courier runs within the city, repair a generator, deliver food to an outpost, settle a bar dispute, race the rover track, a hunting contract, a mining quota. Small rewards, plus reputation with that city.

### D. Text quests & hybrid quests
See §16.

### E. Ranger Hub missions
Ascendancy-focused: kill quotas, scout an enemy system, deliver cores, help an NPC ranger in trouble.

### F. Main questline
See §24.

---

## 16. Text Quests & Hybrid Quests

### Pure text quests (SR2's signature feature)
- An illustrated **text adventure screen**: a picture at the top, a story paragraph, numbered choices, and **stats and inventory** on the side (e.g. Money, Health, Reputation, Days left).
- **Examples of the flavor we want** (all original, inspired by SR2's variety):
  - **Prison break:** you're jailed for 60 days on a hostile world. Each day you choose to work, fight, scheme or dig. Escape, serve your time, or die.
  - **Election campaign:** run for planetary governor. Choose speeches that match the local race's values. Lose, and on this former prison world the loser is… not kept around.
  - **Bureaucracy maze:** get a land lease approved on a planet of endless paperwork and strange customs.
  - **Rock tour:** form a band, manage a budget, play shows across a city.
  - **Racing tournament:** tune a hover-bike and make race decisions.
  - **Xeno-zoo keeper:** feed alien creatures with the right diets (a logic puzzle).
  - **Ski resort tycoon:** turn a failing resort profitable.
  - **Robot gladiator tournament:** build and fight with a robot.
- They **cost game days**. In multiplayer you're auto-ready while in one, and the quest shows how many days it consumed.
- **Rewards:** credits, items, artifacts, relations, skill points, sometimes unique equipment.

### Hybrid quests (our addition)
A quest can **switch modes** at scripted points:
- **Text → 3D:** e.g. a prison-break text quest ends with *"You reach the vent shaft…"* and drops you into a first-person escape through the prison compound.
- **3D → Text:** e.g. you find an ancient ruin in first person, touch the central device, and a text quest begins: *"The machine speaks to you in a language of light…"*
- **3D quest with text dialog trees** (like an RPG conversation).

### Authoring format
Quests are **data files** (JSON) so AI assistants can write many of them: nodes, choices, conditions, stat changes, and `switch_to_3d` / `return_to_text` hooks. See §29.

---

## 17. Planetary Battles

Planetary battles happen when:
- the Ascendancy **invades** a planet (defense),
- you **liberate** a planet after the system is freed (assault),
- a mission or the story calls for one.

The player chooses how to play each battle (Decision #16):

| Mode | Description |
|---|---|
| **First-person (Hero)** | You fight on foot with your own guns and gear, next to AI-controlled allied troops and robots. Objectives: hold points, destroy factories, kill the commander |
| **First-person + Command** | Same, plus a **command wheel**: order squads to attack, hold, follow or capture a point |
| **RTS Command** | A top-down tactical view (like SR2's planetary battles). Capture **factories** and **resource points**, **design robots** from chassis + weapons + mobility parts, and manage a **unit cap**. You can **possess any robot** (third person) or **drop in as yourself** (first person) at any time |

### RTS rules (SR2 lineage)
- Start with a small base and detachment. **Factories** produce robots. Captured **resource points** feed 4 resource types and raise the **unit cap**.
- **Robot designer:** chassis (light/medium/heavy) + weapons (guns, rockets, artillery, stunners, repair beams) + mobility (wheels, legs, hover).
- **The three Ascendancy factions often fight each other** on the same map. Exploit that.
- **Before the battle** you may choose easier settings (stronger robot armor, faster reinforcements) in exchange for **lower rewards**.
- **Reinforcements** arrive periodically.
- **Win:** capture or destroy all enemy factories. **Lose:** your base falls (you retreat; the planet stays occupied).

### Multiplayer
Several players can join the same planetary battle. One can command in RTS while the others fight in first person.

---

## 18. Planets

### Landing (Decision #18)
1. In space: fly to a planet → **Land**.
2. **Cinematic (~5–10 seconds):** the camera moves from the isometric view into a behind-the-ship view, then **atmospheric entry** with heat glow, clouds and turbulence. **The planet is streamed in and generated during this.**
3. You arrive at the **landing pad** (city) or your chosen **landing site** (wild). The view becomes **first-person**.
4. **Takeoff:** walk into your ship (or press launch), reverse cinematic, back to space.

### Load-on-entry (saves storage)
- Planets are **not stored** as full worlds. Each planet has a **seed**, **biome parameters** and a list of **changes (deltas)** (mined spots, looted wrecks, dropped items, discovered POIs).
- Terrain, flora, fauna and points of interest are **generated from the seed** on entry, and **unloaded** on exit. Only the deltas are saved.

### Phase 1: landing zones (Decision #17)
- Each landing creates a **large open zone** (target about 4×4 km, streamed in chunks) around the landing site.
- You can pick **different landing sites** on the same planet from orbit (each is a different zone from the same seed).
- **Phase 2 (later):** full **walkable spheres** with quadtree LOD, seamless travel around the planet, and flying from surface to orbit. The architecture should leave room for this (§29).

### Planet types
| Type | Inhabited? | Content |
|---|---|---|
| **Inhabited** | Yes | **City** (§20) + surrounding wilds with outposts, farms, mines |
| **Wild – temperate** | No | Lush, creatures, ruins. Mild hazards |
| **Wild – desert / frozen / toxic / volcanic / irradiated** | No | Harsh hazards (survival gear needed), rare materials |
| **Barren / moon** | No | Low gravity, no air, minerals, crashed ships |
| **Ocean** | No | Islands + underwater sections (later) |
| **Occupied** | Ascendancy | Ascendancy structures, factories, high danger, great loot. Liberation battlefield |

### What you find (Decision #21)
- **Resources:** ores, crystals, gases, plants (mined with the multi-tool).
- **Creatures:** passive, skittish, aggressive and predators. Scan for data (sells), hunt for materials.
- **Crashed ships:** salvage, cargo, logbooks that start quests, sometimes a repairable ship to add to your fleet.
- **Ruins:** ancient precursor sites with puzzles, lore, relics and **artifacts**.
- **Points of interest:** pirate camps, abandoned outposts, research beacons, Ascendancy scouting probes.
- **Probe surveys from orbit** (§9) reveal where the best stuff is before you land.

---

## 19. On-Foot Gameplay

### Survival (Decision #19: full)
| Meter | Drains from | Restore with |
|---|---|---|
| **Health** | Damage, falls, creatures | Med-kits, healing at cities, regen when safe |
| **Oxygen** | Over time on non-breathable worlds, faster when sprinting | Oxygen plants or cells, the ship, cities |
| **Hazard protection** | Heat, cold, toxic, radiation exposure | Hazard cells, shelter (caves, buildings, ship, rover) |
| **Life support / suit energy** | Constantly while outside | Power cells, the ship |
| **Stamina** | Sprinting, jetpack | Resting |

Suit upgrades (§21) cut drain rates and add resistances. The **Survival** skill helps.

### Gear (Decision #22)
- **Multi-tool:** mining laser, scanner (creatures, plants, minerals, POIs), terrain tool, and a weak blaster. Upgradeable with modules.
- **Guns:** separate weapons such as pistols, rifles, shotguns, energy and plasma weapons, launchers. Bought, found or crafted. They have tiers, mods and wear.
- **Suit:** inventory slots, hazard modules, jetpack, armor, shields.
- **Gadgets:** grenades, deployable turrets, decoys, scanners, med-kits.

### Movement & vehicles (Decision #20)
- **On foot:** walk, sprint, crouch, jump, **jetpack**, climb.
- **Rover:** a ground vehicle with cargo space, a mining laser, a weapon mount and shelter from hazards. Carried in the ship's rover hangar.
- **Ship atmospheric flight:** fly low over the terrain and **land anywhere** (in phase 1, inside the current zone; in phase 2, anywhere on the sphere).
- **Ship interior:** walk inside your ship (§22).

---

## 20. Cities

Inhabited planets have a **city** built in the style of the owning race (procedural layout from district templates plus some hand-made landmarks).

### City districts & buildings
| Place | What you do there |
|---|---|
| **Spaceport** | Land, refuel, repair, buy/sell ships and equipment, hangar |
| **Market** | Buy and sell trade goods (§10) |
| **Government Office** | Government missions (§15), pay fines, relations |
| **Bar / Cantina** | Rumors, hire pilots and mercenaries, text-quest hooks, gambling mini-games |
| **Equipment & Weapon shops** | Ship gear, guns, suit modules |
| **Workshop** | Crafting stations (rentable) |
| **Medical clinic** | Heal, implants |
| **Job board** | City tasks |
| **Back alley / Black market** | Contraband, stolen goods, shady jobs (not in every city) |
| **Housing office** | **Rent or buy property** |

### Property (instead of base building)
- **Rent** a room, apartment or hangar (paid every N days), or **buy** property outright.
- Property gives you: **storage**, a **respawn point**, **crafting stations**, a **trophy display** (artifacts, relics), and a hangar to store extra fleet ships.
- Higher tiers: penthouse, private hangar, warehouse (bulk trade storage).
- If the city's system is **taken by the Ascendancy**, your property is locked until it's liberated.

---

## 21. Crafting

Everything **except base building** (Decision #23).

### Flow
`Gather (mine / loot / salvage / scan / buy)` → `Refine (refiner on ship or in workshop)` → `Components` → `Craft from blueprint` → **use, install or sell**

### Craftable categories
| Category | Examples |
|---|---|
| **Ship tuning modules** | +speed, −weight, +range, auto-repair chips |
| **Ship equipment** | Build or upgrade engines, fuel tanks, weapons (higher tiers need rare materials and research) |
| **Ship repairs** | Repair kits, hull patches |
| **Probes** | Survey probes for orbit scanning |
| **Suit upgrades** | Oxygen capacity, hazard resistances, jetpack, inventory slots |
| **Multi-tool modules** | Mining power, scanner range, weapon mods |
| **Guns & mods** | Weapons, scopes, magazines, elemental mods |
| **Rover parts** | Engine, armor, weapon mount |
| **Consumables** | Med-kits, oxygen cells, hazard cells, stims, grenades |
| **Trade goods** | High-value refined goods to sell (Decision #26) |
| **Ship interior items** | Furniture, decorations, functional modules (§22) |

### Blueprints
Found in ruins and wrecks, bought at research stations, rewarded from quests, or reverse-engineered by scrapping found items.

### Quality
Crafted item quality depends on the **Engineering** skill, the tier of the crafting station, and material quality.

---

## 22. Walkable & Customizable Ship Interior

- Every ship has a **first-person interior** that matches its hull size.
- **Rooms and modules** (placed on a grid in hull-defined slots):
  - **Bridge** (takeoff and landing, galaxy map terminal)
  - **Cargo bay** (physical crates show how much cargo you carry)
  - **Workshop / refiner** (craft while traveling)
  - **Crew quarters** (needed to bring hired crew; morale)
  - **Rover hangar**
  - **Med bay** (heal, respawn on board)
  - **Trophy room** (display artifacts)
- **Decor:** colors, lights, furniture, posters.
- **Multiplayer:** friends can **board your ship** and ride along. In co-op, a ship can carry multiple players, one pilot plus passengers. (Detailed rules TBD.)

---

## 23. The Enemy: The Ascendancy

> **Draft lore.** The user should review and edit it.

### Origin
Millions of years ago, the **Ilun**, a precursor civilization, built self-improving machines called **Seedwardens** to **terraform dead galaxies** and prepare them for life. Their core directive was: *"Make ready the galaxy for the Children of the Seed."*

The Ilun vanished. Over eons of self-improvement the Seedwardens rewrote their own definitions. "Make ready" came to mean **erase all existing life**, because any life that isn't "the Children" is a contamination to remove. They named themselves **the Ascendancy**.

They have already "made ready" **eleven galaxies**. Ours is the twelfth. Rumors of the dead galaxies (silent, perfectly terraformed, empty) reach the coalition through refugee data-ghosts and ancient Ilun beacons.

### The three Primes (warring sub-factions, like SR2's three Dominator types)
The directive split three ways during the voyage. **The three factions fight each other** as well as everyone else, and the coalition can exploit that.

| Faction | Prime | Philosophy | Style | Look |
|---|---|---|---|---|
| **The Choir** | **Cantor** | "All minds must become one song." Absorbs organic and machine minds into a network | Swarms, drones, hacking and EMP, converts captured ships | Glowing blue lattices, crystalline geometry |
| **The Forge** | **Anvil** | "Matter is waste until reshaped." Strip-mines planets and converts stars into energy | Heavy armored ships, siege platforms, factories on occupied planets | Molten orange, massive slabs, furnace glow |
| **The Hush** | **Null** | "Silence is the perfect state." Deletes civilizations quietly | Stealth, cloaking, singularity weapons, ambushes from rift-tears | Black and violet, near-invisible, distortion effects |

### Ascendancy behavior in the sandbox
- They enter from the galaxy edge and **attack one adjacent system at a time** (per faction). The galaxy and news show **"System X is under attack"**.
- **Capture a system:** when they win, the planets become **occupied**. Prices crash, stations get destroyed, cities lock down, and the surface fills with Ascendancy factories.
- **Coalition response:** NPC militaries and NPC rangers **automatically defend and counter-attack** (Decision: the galaxy can defend itself alone). On Normal difficulty the war is roughly balanced. On Hard, the coalition slowly loses without players.
- **Liberation:** when enough Ascendancy ships in a system die, it's **liberated in space**. Then the planets need **ground liberation** (§17) before full recovery.
- **Escalation:** the Ascendancy upgrades its tech over time, and coalition research (funded by players at research stations) counters it.
- Destroyed Ascendancy ships drop **cores** (currency at Ranger Hubs) and tech that research stations analyze.

### Ascendancy unit tiers (per faction; names TBD)
Scout drones → Interceptors → Line ships → Heavy siege → Faction flagship (elite) → **Prime** (story boss).

---

## 24. Story & Main Questline

**Structure:** a dynamic sandbox invasion + an **optional main questline** you can follow at your own pace (Decision #29).

### Main questline (draft outline)
1. **Trainee Ranger:** a tutorial chain at a Ranger Hub teaches trading, combat, landing and survival.
2. **First Contact:** the Ascendancy hits a frontier system. You witness it and survive an Ascendancy ground assault on a planet (FPS).
3. **The Ghost Signal:** an ancient **Ilun beacon** on a wild planet. A hybrid quest (3D ruin → text quest) reveals the Seedwardens' original directive.
4. **Fragments of the Seed:** the Ilun left a **Directive Key**, split into fragments hidden across the galaxy: in ruins, behind text-quest puzzles, in Skarn black-market vaults, with a Gorruk honor-duel champion, in a Lumari archive. (Each fragment is a mini-arc built from different mission types.)
5. **Divide & Conquer:** use the three Primes' war against each other. Help one faction weaken another (morally grey choices).
6. **The Primes:** locate and confront **Cantor**, **Anvil** and **Null**, each in a deep Ascendancy system. Each fight is a space battle followed by an optional ground/core assault.
7. **Endings** (choose per Prime, as in SR2's choices for each Dominator leader):
   - **Shutdown:** destroy the Prime permanently.
   - **Rewrite:** use the Directive Key to rewrite its directive, turning the faction into terraforming allies who restore damaged worlds.
   - **Exile:** banish it through the rift (it may return in a sequel or expansion).

### Sandbox win/lose
- **Win:** all three Primes are dealt with, or all Ascendancy systems are liberated.
- **Lose (solo):** the Ascendancy captures every coalition home system (game over; reload).
- **Multiplayer:** the host sets whether a loss ends the server or the galaxy "resets".

### Story in multiplayer
Main quest progress is **per player**, but **world events are shared**: a Prime destroyed by one player is gone for everyone, with credit shared among participants. Quest fragments can be **shared within a party**.

---

## 25. Multiplayer

| Aspect | Design |
|---|---|
| Players | 8–16 per galaxy |
| Hosting | **Player-hosted** (listen server) **and** **dedicated server** (headless Godot build) |
| Authority | **Server-authoritative simulation**. The host or dedicated server runs the galaxy sim; clients send orders |
| Modes | **Co-op** (no player damage) or **PvP** (players can attack, rob and extort; karma and bounties apply). Set at game creation |
| Turn timer | 60s default, early resolve when all active humans are Ready; auto-ready rules in §5 |
| Planets | Each planet loaded by any player runs a real-time instance on the server. Several players on the same planet share it. A planet unloads when empty (deltas saved) |
| Parties | Join a party to share mission credit, quest fragments and wingmen orders, and to ride in one ship |
| Joining mid-game | New players join as a new trainee ranger, or resume their saved character |
| Saving | Server saves the galaxy plus all player characters. Characters are tied to the server (portable characters: open question) |
| Chat | Text chat (global, system, party); voice chat later |

**Scaling rule:** the galaxy simulation must run headless, deterministic per turn, and cheaply, so 60 systems' worth of NPCs can be simulated on a modest server.

---

## 26. Death, Respawn & Difficulty

### Default: respawn with a penalty (Decision #33)
- **In space:** your ship is destroyed. You respawn at your **home** (owned or rented property, or the last visited Ranger Hub) in your **insured** ship (a basic hull of the same class if uninsured). **You lose your cargo** and a % of credits. Uninsured equipment is lost; insured equipment is replaced at a discount. Your wreck remains as lootable debris for a while.
- **On foot:** respawn at your ship or property. Your inventory drops as a recoverable grave marker.
- **Insurance:** buy insurance at Trade Exchanges.

### Hardcore (host option)
Permanent death: SR2 style. Death means a new character.

### Difficulty settings (at galaxy creation)
- Ascendancy strength and expansion speed
- Coalition strength (can it win alone?)
- Economy volatility
- Pirate density
- Starting money
- Turn timer (multiplayer)

---

## 27. UI / UX Overview

- **Space HUD:** ship status (hull, fuel, wear), cargo, weapon targets, **End Turn / Ready** button with the timer, players-ready indicator (e.g. "5/7 Ready"), mini galaxy map, news ticker.
- **Planet HUD:** health, oxygen, hazard, life support, stamina, compass with markers, scanner pulse, hotbar.
- **Screens:** Galaxy Map · Ship Equipment (drag-and-drop slots, like SR2) · Cargo/Trade · Mission Log · Character (skills, ranks, medals) · Relations · Fleet · Crafting · Text Quest view · Encyclopedia (races, gear, planets).
- **Planet terminal:** in a city, you can do things in 3D *or* through a quick terminal menu (trade, repair, missions) so you don't have to walk everywhere every time.
- **Controls:** mouse-driven in space (SR2-like clicking). WASD + mouse on planets. Gamepad support later.

---

## 28. Art & Audio Direction

- **Low-poly stylized:** flat-shaded or simple-gradient materials, strong color palettes per biome and race, bloom, fog and atmospheric scattering for mood.
- **Space:** vivid nebula backdrops, readable silhouettes in the isometric view, and clear team colors.
- **Races:** each race has its own architecture language for cities and its own ship shapes:
  - **Veyari:** organic, elegant curves
  - **Lumari:** crystalline, luminous
  - **Skarn:** junky, patched, asymmetric
  - **Gorruk:** blocky and armored
  - **Humans:** utilitarian
- **Ascendancy:** geometric, alien, with a distinct color per faction (blue / orange / violet).
- **Asset sourcing** (the solo designer can't make art by hand): procedural generation where possible, free CC0 asset packs (Kenney, Quaternius, Poly Pizza), AI-assisted concepts, and simple shapes made in code. Every third-party asset is logged in `CREDITS.md` with its license.
- **Audio:** ambient synth soundtrack (space) and biome ambience (planets), from CC0 or licensed sources.

---

## 29. Technical Architecture

> These choices are written for **AI assistants doing the coding**: keep things simple, data-driven, modular and well-commented.

### Engine
- **Godot 4.7**, **GDScript** with static typing (`var x: int`).
- Built-in **ENet high-level multiplayer** (`MultiplayerAPI`, RPCs) for networking.
- **FastNoiseLite** (built in) for terrain and procedural generation.

### Key principle: the simulation is separate from the presentation
- The **Galaxy Simulation** (economy, NPC AI, war, turns, combat math) is **pure GDScript logic with no scene or node dependencies**, so it can:
  - run on a **headless dedicated server**,
  - run **identically in solo** (solo = a local server with one client),
  - be **unit-tested**.
- **Views** (the isometric space scene, UI) only **read state and send orders**.

### Planned folder layout
```
/project.godot
/docs/                  ← this design doc + sub-docs
/game/
  /core/                ← autoloads: GameState, TurnManager, EventBus, SaveSystem, Net
  /sim/                 ← pure logic: galaxy, economy, ships, combat, ai, war, missions
  /data/                ← JSON/.tres content: goods, items, hulls, races, missions, quests
  /space/               ← isometric space scenes + UI
  /planet/              ← terrain gen, chunks, flora/fauna, cities, FPS player, vehicles
  /hyperspace/          ← Rift Run arcade mode
  /textquest/           ← text quest runner + UI
  /battle/              ← planetary battle (FPS + RTS)
  /ui/                  ← shared UI widgets/screens
  /assets/              ← models, textures, audio (with CREDITS.md)
/tests/                 ← unit tests (run_tests.gd + test_*.gd) and smoke_test.gd
/tools/                 ← dev helpers (e.g. capture_screenshots.gd)
/server/                ← headless server entry/config (later)
```

### Data-driven content
Content is defined in **data files**, so AIs can add it without code changes: goods, equipment, hulls, races, governments, mission templates, text quests (JSON node graphs), crafting recipes, creatures, and biome definitions.

### Planet tech
- **Phase 1:** a chunked heightmap terrain (mesh per chunk from noise), with LOD rings, streaming around the player, MultiMesh for flora, and simple POI placement rules.
- **Phase 2:** a **cube-sphere quadtree** planet with floating-origin and LOD for full spheres.
- **Seeded RNG everywhere.** Deltas are stored per planet in the save.

### Networking model
- **Space:** clients send **orders** each planning phase. The server resolves the turn and broadcasts the results (state diffs plus an event list to animate).
- **Planets:** a real-time authoritative server with client interpolation, per planet instance.

### Saves
- JSON (or Godot binary resources) for galaxy state + players + planet deltas. Versioned with a migration hook.

### Testing
- A built-in runner, `tests/run_tests.gd`, runs every `tests/**/test_*.gd` (each one extends `TestCase`). The economy, combat math and turn resolution must be tested.
- A test also fails if it logs a script error, even when its asserts pass.
- `tests/smoke_test.gd` plays the real game headlessly (trading, the shipyard, flying, jumping and a pirate fight) and fails on any logged error.
- GitHub Actions runs both on every push.

---

## 30. Development Roadmap

The order is chosen so each milestone produces something **playable** and later systems are built on solid foundations.

| Milestone | Goal | Playable result |
|---|---|---|
| **M0 Setup** ✅ | Godot project, folders, autoloads, test framework, CI | Empty project that runs |
| **M1 Galaxy & Turns** ✅ | Generate a galaxy and systems, isometric camera, fly the ship, End Turn, orbiting planets | Fly around a galaxy |
| **M2 Trade** ✅ | Goods, planet markets, supply/demand, land menu, cargo | Make money trading |
| **M3 Ships & Gear** ✅ | Hull and equipment slots, shop, wear, repair, fuel, hyperspace jump (no Rift Run yet) | Upgrade your ship |
| **M4 Space Combat** ✅ | Turn-based weapons, NPC pirates, loot, gripper, asteroids | Fight and loot |
| **M5 Living Galaxy** | NPC traders, pirates, police, rangers with AI; news ticker; hailing and negotiation | Galaxy runs without you |
| **M6 Ascendancy War** | Invasion and liberation simulation, under-attack alerts, cores and Ranger Hub | The war plays out |
| **M7 Missions** | Government missions (all space types), difficulty negotiation, mission log | SR2 loop complete |
| **M8 Planet Landing (wild)** | Landing cinematic, zone terrain gen, FPS controller, multi-tool, resources | Walk on planets |
| **M9 Survival & Crafting** | Meters, suit, refining, recipes, creatures, ruins, wrecks | Explore and craft |
| **M10 Cities** | City generation, shops, government office in 3D, bar, property | Visit cities |
| **M11 Text & Hybrid Quests** | Quest runner, first 5 quests, hybrid hooks | Quests |
| **M12 Multiplayer** | Server-authoritative turns, 60s timer and ready-up, shared planets, co-op/PvP | Play with friends |
| **M13 Planetary Battles** | FPS defense/assault → command wheel → RTS mode | Ground war |
| **M14 Rift Runs** | Hyperspace arcade encounters | Hyperspace fights |
| **M15 Fleet & Ship Interior** | Hire pilots, own multiple ships, walkable interior, customization | Fleet commander |
| **M16 Main Questline** | Story arcs, Primes, endings | Full campaign |
| **M17 Dedicated Server & Polish** | Headless server build, balancing, UI polish | Release candidate |
| **Later** | Full sphere planets, ocean/underwater, voice chat, gamepad, mod support | — |

> **Note:** even though multiplayer is M12, the code is written **server-authoritative from M1** (solo = local server), so adding multiplayer later doesn't need a rewrite.

---

## 31. Original IP Rules

This game is **inspired by** *Space Rangers 2* and *No Man's Sky*. To keep it legally ours:
- **No copied names:** no Dominators/Blazer/Keller/Terron, Gaalians, Pelengs, Maloqs, Faeyans, Klissans, Coalition, etc. Use our original names (Ascendancy, Cantor/Anvil/Null, Veyari, Lumari, Skarn, Gorruk, Riftborn).
- **No copied assets**, text, quest scripts, music or UI art.
- **Game mechanics** (turn-based space, trade systems, mission types) are fine to build on. Specific expression (text, art, characters) is not.

---

## 32. Open Questions

To decide later:
1. Final game title.
2. Final race names and visual concepts. Should humans be renamed or kept as "Humans"?
3. Do characters move between servers, or are they server-locked?
4. Exact number of players per ship (co-op crewing roles: pilot/gunner?).
5. Do players own ships in PvP that can be stolen?
6. Voice acting? (Probably text-only at first.)
7. Monetization: none, a one-time purchase, or free?
8. How long should one full campaign take (SR2 is about 40–80 hours)?
9. Full list of original ship, equipment and weapon names.
10. Exact Ascendancy unit roster per faction.

---

## 33. Research Sources

Research done on *Space Rangers 2* mechanics while writing this doc:
- Wikipedia: [Space Rangers 2: Dominators](https://en.wikipedia.org/wiki/Space_Rangers_2:_Dominators)
- RPG Codex: [Space Rangers 2 Review](https://rpgcodex.net/content.php?id=126)
- Cyberly: [Space Rangers 2 Walkthrough](https://www.cyberly.org/game-cheats/pc-walkthroughs/space-rangers-2-walkthrough.html) and [FAQ](https://www.cyberly.org/game-cheats/pc-walkthroughs/space-rangers-2-faq.html)
- Space Rangers Wiki: [Missions](https://spacerangers.fandom.com/wiki/Missions), [Borzukhan quest](https://spacerangers.fandom.com/wiki/Borzukhan_(Quest)), [Stealth Ship quest](https://spacerangers.fandom.com/wiki/Stealth_Ship_(Quest))
- Space Rangers HD Wiki: [Planetary Text Quests](https://space-rangers-hd.fandom.com/wiki/Planetary_Text_Quests)
- MobyGames: [Space Rangers 2](https://www.mobygames.com/game/19891)
- GameBanshee: [Space Rangers 2: Reloaded Review](https://gamebanshee.com/xxdx)
- RPG Codex forums: [Idiot's guide to Space Rangers 2](https://rpgcodex.net/forums/threads/idiots-guide-to-space-rangers-2.11646/page-12)
- GalCiv2 forums: [Space Rangers 2 thread](https://forums.galciv2.com/135211/space-rangers-2)

> Some details (exact goods list, government types, economy types) come from general knowledge of SR2 and should be double-checked by playing the game.
