class_name Combat
extends RefCounted
## Space combat, loot and asteroids (docs/MASTER_DESIGN.md section 6). Pure logic.
##
## Combat happens in the normal turns, like everything else. Each ship has one target
## (a ship or an asteroid). Every day, after everyone has moved, every weapon whose target
## is in range fires once. All ships fire at the same moment, so a ship destroyed this
## turn still gets its last shots off. Then:
##   - destroyed NPC ships leave a cargo container (part of their cargo plus salvage),
##     and the Ranger Corps pays a bounty (to the player or an NPC ranger) for every
##     pirate destroyed;
##   - a destroyed player ship is towed to a planet by the Ranger Corps (Decision #52);
##   - ships with a gripper pick up containers within its range.
##
## Shields take a share off every hit (and wear a little each time).
## Shooting at a ship that is not a pirate is a crime (see Law).
##
## Ships in orbit of an inhabited planet are protected by its defenses: they can't shoot
## or be shot. That is where traders (and players) flee to. Pilots wanted by the planet's
## race get no protection.

const TARGET_SHIP := "ship"
const TARGET_ASTEROID := "asteroid"

const SPLASH_DAMAGE := 0.5 ## Fragment weapons hit nearby enemies for half damage.
const ENGAGE_FACTOR := 0.8 ## Chasing ships stop at 80% of their shortest weapon range.
const MIN_ENGAGE_DISTANCE := 60.0
const CARGO_SURVIVES := Vector2(0.4, 0.8) ## Share of a destroyed ship's cargo left in the wreck.
const SALVAGE_PER_HULL_TON := 0.04 ## Salvage units per ton of hull size (a Courier gives about 4).
const RESCUE_FEE := 0.2 ## Share of the player's credits the rescue costs.
const RESCUE_HULL := 0.3 ## Hull left after a rescue (share of max).
const ASTEROID_RESPAWN_DAYS := Vector2i(20, 40)

# Event types.
## A ship spotted the ship `ship_id` and is attacking it. {"ship_id" (victim), "attacker_id"}
const EVENT_UNDER_ATTACK := "under_attack"
## A weapon fired. {"ship_id" (shooter), "system_id", "target_kind", "target_id",
## "weapon_type", "damage" (after the shield), "blocked" (stopped by the shield), "from", "to" (positions)}
const EVENT_SHOT := "shot"
## {"ship_id" (the destroyed ship), "system_id", "killer_id", "killer_name", "killer_role", "name",
## "role", "bounty", "position"}
const EVENT_SHIP_DESTROYED := "ship_destroyed"
## {"ship_id" (shooter), "system_id", "asteroid_id", "position", "minerals"}
const EVENT_ASTEROID_DESTROYED := "asteroid_destroyed"
## The player's ship was destroyed and towed to a planet.
## {"ship_id", "system_id" (where it was destroyed), "position" (ditto), "planet_id" (where it
## was towed to), "rescue_system_id", "fee", "lost_cargo" (units left in a container)}
const EVENT_RESCUED := "rescued"
## A gripper picked up cargo. {"ship_id", "cargo": {good id: units}, "left_behind": bool}
const EVENT_COLLECTED := "collected"


# --- Questions about targets -------------------------------------------------------

## True if the ship is in orbit of an inhabited planet (protected by its defenses),
## unless that planet's race wants the pilot.
static func is_protected(galaxy: GalaxyData, ship: ShipData) -> bool:
	var planet := Trade.market_planet(galaxy, ship)
	return planet != null and not Law.is_wanted_by(ship, planet.race_id)


## Can `attacker` shoot at `victim` right now (ignoring range)?
static func can_attack_ship(galaxy: GalaxyData, attacker: ShipData, victim: ShipData) -> bool:
	if victim == null or victim == attacker or victim.in_hyperspace or attacker.in_hyperspace:
		return false
	if victim.system_id != attacker.system_id or victim.hull_hp <= 0.0:
		return false
	return not is_protected(galaxy, victim) and not is_protected(galaxy, attacker)


## Does the ship's target still exist in its system?
static func target_exists(galaxy: GalaxyData, ship: ShipData) -> bool:
	match ship.target_kind:
		TARGET_SHIP:
			var other := galaxy.get_ship(ship.target_id)
			return other != null and other != ship and not other.in_hyperspace and not ship.in_hyperspace and other.system_id == ship.system_id
		TARGET_ASTEROID:
			var asteroid := galaxy.get_system(ship.system_id).get_asteroid(ship.target_id)
			return asteroid != null and asteroid.exists() and not ship.in_hyperspace
	return false


## Where the ship's target is. Only call when target_exists() is true.
static func target_position(galaxy: GalaxyData, ship: ShipData) -> Vector2:
	if ship.target_kind == TARGET_SHIP:
		return galaxy.get_ship(ship.target_id).position
	return galaxy.get_system(ship.system_id).get_asteroid(ship.target_id).position()


## Clears the ship's target if it was destroyed or left the system.
static func forget_lost_target(galaxy: GalaxyData, ship: ShipData) -> void:
	if ship.has_target() and not target_exists(galaxy, ship):
		ship.clear_target()


## How close a chasing ship gets to its target.
static func engage_distance(ship: ShipData) -> float:
	return maxf(MIN_ENGAGE_DISTANCE, Equipment.min_weapon_range(ship) * ENGAGE_FACTOR)


## How strong a fighter the ship is: hull (made tougher by the shield) times the damage
## its weapons deal per day. Used when ships size each other up (see Comms).
static func strength(ship: ShipData) -> float:
	var damage_per_day := 0.0
	for weapon in ship.weapons:
		if Equipment.can_fire(weapon):
			var span := Equipment.weapon_damage(weapon)
			damage_per_day += (span.x + span.y) / 2.0
	return ship.hull_hp / maxf(0.1, 1.0 - Equipment.shield_absorb(ship)) * damage_per_day


## Can the ship fire at its target this turn (range aside)?
static func can_fire_at_target(galaxy: GalaxyData, ship: ShipData) -> bool:
	if ship.weapons.is_empty() or not target_exists(galaxy, ship):
		return false
	if ship.target_kind == TARGET_SHIP:
		return can_attack_ship(galaxy, ship, galaxy.get_ship(ship.target_id))
	return not is_protected(galaxy, ship)


# --- The combat phase of a turn ------------------------------------------------------

## Runs after all ships have moved: weapons fire, ships and asteroids break apart,
## grippers collect loot.
static func resolve(galaxy: GalaxyData, events: Array[Dictionary]) -> void:
	# 1. Everyone fires at once. Damage to ships is added up and applied afterwards.
	var damage := {} ## ship id -> damage taken this turn
	var attackers := {} ## ship id -> Array of ids of the ships that hit it
	for ship in galaxy.ships:
		forget_lost_target(galaxy, ship)
		if can_fire_at_target(galaxy, ship):
			_fire_weapons(galaxy, ship, damage, attackers, events)

	# 2. Hulls take the damage. Victims fight back (or flee, if they are traders).
	#    Shooting at peaceful ships is a crime.
	for ship_id: int in damage:
		var victim := galaxy.get_ship(ship_id)
		victim.hull_hp = maxf(0.0, victim.hull_hp - float(damage[ship_id]))
		var attacker := galaxy.get_ship(attackers[ship_id][0])
		if not victim.has_target() and not victim.weapons.is_empty():
			victim.target_kind = TARGET_SHIP
			victim.target_id = attacker.id
			victim.pursue = not victim.is_player # NPCs chase whoever shot them.
		if victim.role == ShipData.ROLE_TRADER:
			flee_to_planet(galaxy, victim)
		for attacker_id: int in attackers[ship_id]:
			victim.truce.erase(attacker_id) # Any deal with the shooter is off.
			var shooter := galaxy.get_ship(attacker_id)
			if shooter.is_player:
				Law.commit_crime(galaxy, shooter, victim, Law.CRIME_ASSAULT, events)

	# 3. Ships with no hull left are destroyed.
	for ship_id: int in damage:
		var wreck := galaxy.get_ship(ship_id)
		if wreck.hull_hp > 0.0:
			continue
		var hit_by: Array = attackers[ship_id]
		var killer_id: int = hit_by[0]
		if hit_by.has(galaxy.player_ship_id):
			killer_id = galaxy.player_ship_id # The player gets the bounty if they helped.
		if wreck.is_player:
			_rescue_player(galaxy, wreck, events)
		else:
			var killer := galaxy.get_ship(killer_id) # null if it was destroyed this turn too.
			if killer != null and killer.is_player:
				Law.commit_crime(galaxy, killer, wreck, Law.CRIME_MURDER, events)
			_destroy_npc(galaxy, wreck, killer_id, events)

	# 4. Grippers pick up cargo containers.
	for ship in galaxy.ships:
		_collect_loot(galaxy, ship, events)


## Once a day: containers drift away, broken asteroids are replaced, asteroids orbit.
static func daily_upkeep(galaxy: GalaxyData) -> void:
	for system in galaxy.systems:
		for container in system.loot.duplicate():
			container.days_left -= 1
			if container.days_left <= 0:
				system.loot.erase(container)
		for asteroid in system.asteroids:
			asteroid.advance(1)
			if not asteroid.exists():
				asteroid.respawn_days -= 1
				if asteroid.respawn_days <= 0:
					asteroid.hp = asteroid.hp_max
					asteroid.respawn_days = 0


static func _fire_weapons(galaxy: GalaxyData, ship: ShipData, damage: Dictionary, attackers: Dictionary, events: Array[Dictionary]) -> void:
	var target_at := target_position(galaxy, ship)
	var distance := ship.position.distance_to(target_at)
	for i in ship.weapons.size():
		if not target_exists(galaxy, ship):
			return # An asteroid broke up from an earlier shot.
		var weapon := ship.weapons[i]
		if distance > Equipment.weapon_range(weapon) or not Equipment.can_fire(weapon):
			continue
		# Seeded from (galaxy, day, ship, weapon) so every computer gets the same result.
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id, i, "shot"])
		var span := Equipment.weapon_damage(weapon)
		var hit := float(roundi(rng.randf_range(span.x, span.y)))
		if weapon.max_ammo() > 0:
			weapon.ammo -= 1
		Equipment.wear_weapon(weapon)
		var event := {"type": EVENT_SHOT, "ship_id": ship.id, "system_id": ship.system_id, "target_kind": ship.target_kind,
			"target_id": ship.target_id, "weapon_type": Equipment.weapon_type(weapon), "damage": int(hit), "blocked": 0,
			"from": ship.position, "to": target_at}
		events.append(event)
		if ship.target_kind == TARGET_ASTEROID:
			_damage_asteroid(galaxy, ship, hit, events)
			continue
		var target := galaxy.get_ship(ship.target_id)
		var landed := _shielded(target, hit)
		event["damage"] = int(landed)
		event["blocked"] = int(hit - landed)
		_add_damage(damage, attackers, target.id, landed, ship.id)
		# Fragment weapons also hit the target's allies close to it.
		var splash := float(weapon.stats().get("splash", 0.0))
		if splash > 0.0:
			for other in galaxy.ships_in_system(ship.system_id):
				if other != target and other.is_pirate() == target.is_pirate() and other.position.distance_to(target_at) <= splash \
						and can_attack_ship(galaxy, ship, other):
					_add_damage(damage, attackers, other.id, _shielded(other, roundf(hit * SPLASH_DAMAGE)), ship.id)


## The damage left of a hit after the victim's shield (which wears a little).
static func _shielded(victim: ShipData, hit: float) -> float:
	var absorb := Equipment.shield_absorb(victim)
	if absorb <= 0.0:
		return hit
	Equipment.wear_shield(victim)
	return float(roundi(hit * (1.0 - absorb)))


static func _add_damage(damage: Dictionary, attackers: Dictionary, victim_id: int, amount: float, attacker_id: int) -> void:
	damage[victim_id] = float(damage.get(victim_id, 0.0)) + amount
	if not attackers.has(victim_id):
		attackers[victim_id] = []
	if not attackers[victim_id].has(attacker_id):
		attackers[victim_id].append(attacker_id)


static func _damage_asteroid(galaxy: GalaxyData, ship: ShipData, amount: float, events: Array[Dictionary]) -> void:
	var system := galaxy.get_system(ship.system_id)
	var asteroid := system.get_asteroid(ship.target_id)
	asteroid.hp = maxf(0.0, asteroid.hp - amount)
	if asteroid.exists():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, system.id, asteroid.id, "asteroid"])
	asteroid.respawn_days = rng.randi_range(ASTEROID_RESPAWN_DAYS.x, ASTEROID_RESPAWN_DAYS.y)
	system.add_loot(asteroid.position(), {"minerals": asteroid.minerals})
	events.append({"type": EVENT_ASTEROID_DESTROYED, "ship_id": ship.id, "system_id": system.id, "asteroid_id": asteroid.id,
		"position": asteroid.position(), "minerals": asteroid.minerals})
	for other in galaxy.ships_in_system(system.id):
		if other.target_kind == TARGET_ASTEROID and other.target_id == asteroid.id:
			other.clear_target()


## A trader under fire runs for the nearest inhabited planet (whose defenses protect it).
static func flee_to_planet(galaxy: GalaxyData, ship: ShipData) -> void:
	if ship.target_planet_id >= 0 or ship.hull_hp <= 0.0:
		return # Already fleeing (or destroyed).
	var planet := nearest_inhabited_planet(galaxy.get_system(ship.system_id), ship.position)
	if planet != null:
		TurnResolver.apply_order(galaxy, ship, {"type": "move_to_planet", "planet_id": planet.id})


static func nearest_inhabited_planet(system: StarSystemData, from: Vector2) -> PlanetData:
	var best: PlanetData = null
	for planet in system.inhabited_planets():
		if best == null or planet.position().distance_to(from) < best.position().distance_to(from):
			best = planet
	return best


static func _destroy_npc(galaxy: GalaxyData, ship: ShipData, killer_id: int, events: Array[Dictionary]) -> void:
	var system := galaxy.get_system(ship.system_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id, "wreck"])
	# Part of the cargo survives, plus scrap from the hull.
	var wreckage := {}
	for good_id: String in ship.cargo:
		var kept := floori(ship.cargo_amount(good_id) * rng.randf_range(CARGO_SURVIVES.x, CARGO_SURVIVES.y))
		if kept > 0:
			wreckage[good_id] = kept
	var hull_size := float(ship.hull.stats().get("size", 80)) if ship.hull != null else 80.0
	var salvage := maxi(1, roundi(hull_size * SALVAGE_PER_HULL_TON * rng.randf_range(0.7, 1.3)))
	wreckage["salvage"] = int(wreckage.get("salvage", 0)) + salvage
	system.add_loot(ship.position, wreckage)

	# The Ranger Corps pays the bounty on pirates to rangers (the player or NPC rangers).
	var bounty := 0
	var killer := galaxy.get_ship(killer_id)
	if killer != null and ship.is_pirate() and (killer.is_player or killer.role == ShipData.ROLE_RANGER):
		bounty = ship.bounty
		killer.credits += bounty
		Law.pirate_destroyed(killer, ship)
	events.append({"type": EVENT_SHIP_DESTROYED, "ship_id": ship.id, "system_id": system.id, "killer_id": killer_id,
		"killer_name": killer.name if killer != null else "", "killer_role": killer.role if killer != null else "",
		"name": ship.name, "role": ship.role, "bounty": bounty, "position": ship.position})
	_forget_ship_as_target(galaxy, ship.id)
	galaxy.remove_ship(ship.id)


## The Ranger Corps tows the wreck of the player's ship to the nearest inhabited planet
## (in this system if possible, otherwise their home system). The cargo is left behind in
## a container, the rescue costs part of their credits, and the hull is barely patched up.
static func _rescue_player(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	var system := galaxy.get_system(ship.system_id)
	var wreck_system_id := system.id
	var wreck_position := ship.position
	var lost_cargo := ship.cargo_used()
	system.add_loot(ship.position, ship.cargo)
	ship.cargo.clear()
	var fee := roundi(ship.credits * RESCUE_FEE)
	ship.credits -= fee

	var planet := nearest_inhabited_planet(system, ship.position)
	if planet == null:
		system = galaxy.home_system_of(ship.race_id)
		if system == null:
			system = galaxy.systems[0]
		planet = nearest_inhabited_planet(system, Vector2.ZERO)
		if planet == null:
			planet = system.planets[0]
	ship.system_id = system.id
	ship.clear_course()
	ship.clear_target()
	ship.orbiting_planet_id = planet.id
	ship.orbit_offset = Vector2.from_angle(planet.orbit_angle + PI) * (planet.radius + TurnResolver.PLANET_ARRIVAL_MARGIN)
	ship.position = planet.position() + ship.orbit_offset
	ship.hull_hp = ceilf(ship.hull_hp_max * RESCUE_HULL)
	_forget_ship_as_target(galaxy, ship.id)
	events.append({"type": EVENT_RESCUED, "ship_id": ship.id, "system_id": wreck_system_id, "position": wreck_position,
		"planet_id": planet.id, "rescue_system_id": system.id, "fee": fee, "lost_cargo": lost_cargo})


static func _forget_ship_as_target(galaxy: GalaxyData, ship_id: int) -> void:
	for other in galaxy.ships:
		if other.target_kind == TARGET_SHIP and other.target_id == ship_id:
			other.clear_target()


static func _collect_loot(galaxy: GalaxyData, ship: ShipData, events: Array[Dictionary]) -> void:
	if ship.gripper == null or ship.in_hyperspace:
		return
	var system := galaxy.get_system(ship.system_id)
	var reach := Equipment.gripper_range(ship)
	var collected := {}
	var left_behind := false
	for container in system.loot.duplicate():
		if ship.position.distance_to(container.position) > reach:
			continue
		for good_id: String in container.cargo.keys():
			var take := mini(int(container.cargo[good_id]), ship.cargo_free())
			if take > 0:
				ship.add_cargo(good_id, take)
				collected[good_id] = int(collected.get(good_id, 0)) + take
				container.cargo[good_id] = int(container.cargo[good_id]) - take
			if int(container.cargo[good_id]) <= 0:
				container.cargo.erase(good_id)
			else:
				left_behind = true
		if container.is_empty():
			system.loot.erase(container)
	if not collected.is_empty():
		events.append({"type": EVENT_COLLECTED, "ship_id": ship.id, "cargo": collected, "left_behind": left_behind})
