class_name Comms
extends RefCounted
## Hailing ships and planets (docs/MASTER_DESIGN.md section 7). Pure logic, used through
## the "hail" order. The other side answers based on its role, its race's personality
## ("personality" in races.json: greed, courage, helpful) and how the two ships compare
## in a fight (Combat.strength). Answers are rolled from the galaxy seed, the day and both
## ships, so asking the same thing twice on the same day gets the same answer.
##
## Ships:
##   news      - any ship: a tip about prices or pirates, if they feel like talking.
##   help      - police and rangers: join your attack on the pirate you are targeting.
##   demand    - traders: drop half their cargo, or else. A crime (extortion, see Law).
##   bribe     - pirates (and police, if they want you): pay them to leave you alone.
##   threaten  - pirates: back off, or else. Works if you are clearly stronger.
##   surrender - pirates: hand over half your cargo so they let you go.
## Planets:
##   news      - the latest headlines.
##   pay_fine  - pay what you owe the planet's race (see Law).
## The numbers are in the "comms" section of game/data/npcs.json.

const TARGET_SHIP := "ship"
const TARGET_PLANET := "planet"

## A hail was answered. {"ship_id", "target_kind", "target_id", "option", "accepted", "reply"}
const EVENT_HAIL := "hail"

## Button labels for the options.
const OPTION_NAMES := {"news": "Ask for news", "help": "Ask for help", "demand": "Demand cargo",
	"bribe": "Offer a bribe", "threaten": "Threaten", "surrender": "Surrender cargo", "pay_fine": "Pay your fine"}


static func settings() -> Dictionary:
	return GameData.npcs().get("comms", {})


## What a bribe costs `ship` right now.
static func bribe_cost(ship: ShipData) -> int:
	var comms := settings()
	return roundi(float(comms.get("bribe_base", 200)) + float(comms.get("bribe_share", 0.1)) * ship.credits)


## The options for hailing this ship or planet, in the order the UI shows them.
static func options(galaxy: GalaxyData, ship: ShipData, target_kind: String, target_id: int) -> Array[String]:
	var result: Array[String] = ["news"]
	if target_kind == TARGET_PLANET:
		var planet := galaxy.get_system(ship.system_id).get_planet(target_id)
		if planet != null and Law.is_wanted_by(ship, planet.race_id):
			result.append("pay_fine")
		return result
	var other := galaxy.get_ship(target_id)
	if other == null:
		return result
	match other.role:
		ShipData.ROLE_TRADER:
			result.append("demand")
		ShipData.ROLE_PIRATE:
			result.append_array(["bribe", "threaten", "surrender"])
		ShipData.ROLE_POLICE:
			result.append("help")
			if Law.is_wanted_by(ship, other.race_id):
				result.append("bribe")
		ShipData.ROLE_RANGER:
			result.append("help")
	return result


## Hails a ship or planet with one of options(). Returns "" when they answered (the answer
## is in an EVENT_HAIL event), or a message explaining why the hail can't be made.
static func hail(galaxy: GalaxyData, ship: ShipData, target_kind: String, target_id: int, option: String,
		events: Array[Dictionary]) -> String:
	var answer := {}
	if target_kind == TARGET_PLANET:
		var planet := galaxy.get_system(ship.system_id).get_planet(target_id)
		if planet == null or not planet.inhabited:
			return "Nobody answers: that planet is uninhabited."
		if not option in options(galaxy, ship, target_kind, target_id):
			return "You can't ask that here."
		if option == "pay_fine":
			var error := Law.pay_fine(ship, planet, events)
			if error != "":
				return error
			answer = _reply(true, "Your fine is paid. Welcome back, pilot.")
		else:
			answer = _reply(true, _planet_news(galaxy))
	elif target_kind == TARGET_SHIP:
		var other := galaxy.get_ship(target_id)
		if other == null or other == ship or other.in_hyperspace or other.system_id != ship.system_id:
			return "That ship isn't here."
		if other.position.distance_to(ship.position) > Equipment.radar_range(ship):
			return "%s is out of radar range." % other.name
		if not option in options(galaxy, ship, target_kind, target_id):
			return "You can't ask that of %s." % other.name
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([galaxy.galaxy_seed, galaxy.day, ship.id, other.id, option])
		match option:
			"news":
				answer = _news(galaxy, ship, other, rng)
			"help":
				answer = _help(galaxy, ship, other, rng)
			"demand":
				answer = _demand(galaxy, ship, other, rng, events)
			"bribe":
				answer = _bribe(ship, other, rng)
			"threaten":
				answer = _threaten(galaxy, ship, other, events)
			"surrender":
				answer = _surrender(ship, other)
		if answer.has("error"):
			return answer["error"]
	else:
		return "Nobody to hail."
	events.append({"type": EVENT_HAIL, "ship_id": ship.id, "target_kind": target_kind, "target_id": target_id,
		"option": option, "accepted": answer["accepted"], "reply": answer["reply"]})
	return ""


static func _reply(accepted: bool, text: String) -> Dictionary:
	return {"accepted": accepted, "reply": text}


## A race's personality trait (0-1).
static func trait_of(ship: ShipData, trait_name: String) -> float:
	return float(GameData.race(ship.race_id).get("personality", {}).get(trait_name, 0.5))


# --- Ship options ------------------------------------------------------------------

static func _news(galaxy: GalaxyData, ship: ShipData, other: ShipData, rng: RandomNumberGenerator) -> Dictionary:
	if other.is_pirate():
		if Law.pirates_ignore(ship):
			return _reply(true, "Fair skies, friend. Watch out for the police around here.")
		return _reply(false, "Talk? The only thing we want to hear from you is your cargo hitting space.")
	if other.role == ShipData.ROLE_POLICE and Law.is_wanted_by(ship, other.race_id):
		return _reply(false, "You are wanted by the %s for %d cr. Pay your fine at one of our planets." % [
			GameData.race(other.race_id).get("name", "?"), int(ship.wanted[other.race_id])])
	if rng.randf() > trait_of(other, "helpful") + 0.3:
		return _reply(false, "We have nothing to say to you.")
	var pirates := 0
	for nearby in galaxy.ships_in_system(ship.system_id):
		if nearby.is_pirate():
			pirates += 1
	if pirates > 0 and rng.randf() < 0.5:
		return _reply(true, "Careful: %d pirate ship%s prowl this system." % [pirates, "" if pirates == 1 else "s"])
	return _reply(true, _price_tip(galaxy, ship, rng))


## "Technology fetches a good price on X in the Y system", for a random legal good and the
## best planet for it within the asking ship's jump range.
static func _price_tip(galaxy: GalaxyData, ship: ShipData, rng: RandomNumberGenerator) -> String:
	var good_id := NpcSpawner.TRADER_GOODS[rng.randi_range(0, NpcSpawner.TRADER_GOODS.size() - 1)]
	var best_planet: PlanetData = null
	var best_system: StarSystemData = null
	var best_ratio := 0.0
	for system in galaxy.systems:
		if galaxy.distance_between(ship.system_id, system.id) > ship.jump_range:
			continue
		for planet in system.inhabited_planets():
			var ratio := Economy.price_ratio(planet, good_id)
			if not Economy.is_illegal(planet, good_id) and ratio > best_ratio:
				best_ratio = ratio
				best_planet = planet
				best_system = system
	if best_planet == null:
		return "Quiet times. Nothing to report."
	return "Word is %s fetches a good price on %s in the %s system." % [
		str(GameData.good(good_id).get("name", good_id)).to_lower(), best_planet.name, best_system.name]


static func _help(galaxy: GalaxyData, ship: ShipData, other: ShipData, rng: RandomNumberGenerator) -> Dictionary:
	var pirate: ShipData = null
	if ship.target_kind == Combat.TARGET_SHIP and Combat.target_exists(galaxy, ship):
		pirate = galaxy.get_ship(ship.target_id)
	if pirate == null or not pirate.is_pirate():
		return {"error": "Target a pirate first, then ask for help."}
	if other.has_target():
		return _reply(false, "We're busy with a fight of our own!")
	if pirate.position.distance_to(other.position) > float(settings().get("help_range", 1200.0)):
		return _reply(false, "That pirate is too far away for us.")
	if other.role == ShipData.ROLE_RANGER and rng.randf() > trait_of(other, "helpful") + 0.3:
		return _reply(false, "Sorry, ranger. You're on your own this time.")
	if TurnResolver.apply_order(galaxy, other, {"type": "attack", "target_kind": Combat.TARGET_SHIP, "target_id": pirate.id}) != "":
		return _reply(false, "We can't reach that ship right now.")
	return _reply(true, "On our way! Let's take %s down together." % pirate.name)


static func _demand(galaxy: GalaxyData, ship: ShipData, other: ShipData, rng: RandomNumberGenerator, events: Array[Dictionary]) -> Dictionary:
	if ship.weapons.is_empty():
		return {"error": "You have no weapons to back up your demand."}
	if Combat.is_protected(galaxy, other):
		return _reply(false, "Try anything and this planet's guns will answer. Get lost.")
	if other.cargo_used() == 0:
		return _reply(false, "Our hold is empty. There's nothing to take!")
	# Unarmed traders give in unless they are brave (then they try to outrun you).
	if rng.randf() < trait_of(other, "courage") * 0.6:
		Combat.flee_to_planet(galaxy, other)
		return _reply(false, "Never! We'd rather run for it.")
	var dropped := _hand_over(other, float(settings().get("demand_share", 0.5)))
	galaxy.get_system(other.system_id).add_loot(other.position, dropped)
	Law.commit_crime(galaxy, ship, other, Law.CRIME_EXTORTION, events)
	Combat.flee_to_planet(galaxy, other)
	return _reply(true, "Don't shoot! We're dropping the cargo. Pick it up with your gripper.")


static func _bribe(ship: ShipData, other: ShipData, rng: RandomNumberGenerator) -> Dictionary:
	if other.has_truce_with(ship.id):
		return _reply(true, "We already have a deal. Don't push your luck.")
	var cost := bribe_cost(ship)
	if ship.credits < cost:
		return {"error": "You can't afford the bribe (%d cr)." % cost}
	var greed := trait_of(other, "greed")
	var chance := greed * 0.8 + 0.1 if other.role == ShipData.ROLE_POLICE else greed + 0.25
	if rng.randf() > chance:
		return _reply(false, "Keep your money. We know what we want.")
	ship.credits -= cost
	other.credits += cost
	_make_truce(other, ship)
	if other.role == ShipData.ROLE_POLICE:
		return _reply(true, "Move along, pilot. We didn't see anything. (Paid %d cr.)" % cost)
	return _reply(true, "Pleasure doing business. We never saw you. (Paid %d cr.)" % cost)


static func _threaten(galaxy: GalaxyData, ship: ShipData, other: ShipData, events: Array[Dictionary]) -> Dictionary:
	if other.has_truce_with(ship.id):
		return _reply(true, "We're leaving, we're leaving!")
	var theirs := Combat.strength(other) * float(settings().get("threat_ratio", 1.5)) * (0.5 + trait_of(other, "courage"))
	if Combat.strength(ship) > theirs:
		_make_truce(other, ship)
		# Run away from the ship that scared them.
		var system := galaxy.get_system(other.system_id)
		var away := (other.position - ship.position).normalized()
		var point := (other.position + away * 500.0).limit_length(system.jump_radius * 0.9)
		TurnResolver.apply_order(galaxy, other, {"type": "move_to_point", "point": point})
		return _reply(true, "All right, all right! We're leaving.")
	if not other.has_target() and Combat.can_attack_ship(galaxy, other, ship):
		other.clear_course()
		other.target_kind = Combat.TARGET_SHIP
		other.target_id = ship.id
		other.pursue = true
		events.append({"type": Combat.EVENT_UNDER_ATTACK, "ship_id": ship.id, "attacker_id": other.id})
	return _reply(false, "Big words for such a small ship. Let's see you back them up!")


static func _surrender(ship: ShipData, other: ShipData) -> Dictionary:
	if other.has_truce_with(ship.id):
		return _reply(true, "You already paid. Now get out of our sight.")
	if ship.cargo_used() == 0:
		return _reply(false, "An empty hold? Then we'll take your ship apart instead.")
	var taken := _hand_over(ship, float(settings().get("surrender_share", 0.5)))
	for good_id: String in taken:
		other.add_cargo(good_id, int(taken[good_id]))
	_make_truce(other, ship)
	return _reply(true, "Smart choice. Now get out of our sight.")


# --- Planets -------------------------------------------------------------------------

static func _planet_news(galaxy: GalaxyData) -> String:
	if galaxy.news.is_empty():
		return "All quiet in the galaxy today."
	var lines: Array[String] = []
	for item in galaxy.news.slice(0, 3):
		lines.append("Day %d: %s" % [int(item["day"]), item["text"]])
	return "\n".join(lines)


# --- Helpers -------------------------------------------------------------------------

## `ship` agrees not to attack `other` for a while, and stops if it was.
static func _make_truce(ship: ShipData, other: ShipData) -> void:
	ship.truce[other.id] = int(settings().get("truce_days", 6))
	if ship.target_kind == Combat.TARGET_SHIP and ship.target_id == other.id:
		ship.clear_target()


## Takes a share (rounded up) of every good out of the ship's hold. Returns {good id: units}.
static func _hand_over(ship: ShipData, share: float) -> Dictionary:
	var taken := {}
	for good_id: String in ship.cargo.keys():
		var units := ceili(ship.cargo_amount(good_id) * share)
		if units > 0:
			ship.add_cargo(good_id, -units)
			taken[good_id] = units
	return taken
