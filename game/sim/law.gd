class_name Law
extends RefCounted
## Karma, crimes, fines and "wanted" status (docs/MASTER_DESIGN.md section 12). Pure logic.
## The numbers are in the "law" section of game/data/world.json.
##
## Attacking, destroying or robbing a ship that is not a pirate is a crime. Karma always
## goes down. In a system with a government (any inhabited planet that is not an anarchy)
## the crime is also reported to the system's race: you are fined and become *wanted* by
## that race until you pay the fine (hail one of their planets) or it is slowly forgotten.
## While a race wants you:
##   - its police attack you on sight,
##   - its planets refuse to trade with you or repair your ship, and
##   - their defenses no longer protect you in orbit.
## Destroying pirates raises karma. Pirates leave pilots with very low karma alone: they
## see them as one of their own.

const CRIME_ASSAULT := "assault" ## Shooting at a peaceful ship.
const CRIME_MURDER := "murder" ## Destroying one.
const CRIME_EXTORTION := "extortion" ## Forcing one to drop its cargo (see Comms).

## A pilot committed a crime. {"ship_id" (the criminal), "system_id", "crime", "victim_id",
## "victim_name", "victim_role", "fine", "race_id" ("" if nobody fined them),
## "newly_wanted" (true if that race did not want them before)}
const EVENT_CRIME := "crime"
## Paid off a fine. {"ship_id", "planet_id", "race_id", "credits"}
const EVENT_FINE_PAID := "fine_paid"


static func settings() -> Dictionary:
	return GameData.load_json("world.json").get("law", {})


## How many police ships patrol the system: the most any of its planets' governments
## sends, plus one in a race's home system. 0 means there is no law here.
static func police_count(system: StarSystemData) -> int:
	var count := 0
	for planet in system.inhabited_planets():
		count = maxi(count, int(GameData.government(planet.government_id).get("police", 0)))
	if count > 0 and system.is_home:
		count += 1
	return count


static func has_law(system: StarSystemData) -> bool:
	return police_count(system) > 0


static func is_wanted_by(ship: ShipData, race_id: String) -> bool:
	return int(ship.wanted.get(race_id, 0)) > 0


## The reputation name for a karma value, e.g. "Neutral" or "Hero".
static func reputation(karma: int) -> String:
	for level: Dictionary in settings().get("reputation", []):
		if karma >= int(level.get("min", 0)):
			return str(level.get("name", "?"))
	return "?"


## Pirates leave pilots this bad alone.
static func pirates_ignore(ship: ShipData) -> bool:
	return ship.karma <= int(settings().get("pirate_friend_karma", -30))


## Records a crime by `criminal` against `victim`. Pirates are criminals anyway, so only
## other pilots (the player, for now) are punished.
static func commit_crime(galaxy: GalaxyData, criminal: ShipData, victim: ShipData, crime: String, events: Array[Dictionary]) -> void:
	if criminal.is_pirate() or victim.is_pirate():
		return
	var law := settings()
	criminal.karma += int(law.get(crime + "_karma", 0))
	var system := galaxy.get_system(criminal.system_id)
	var fine := 0
	var race_id := ""
	var newly_wanted := false
	if has_law(system):
		race_id = system.race_id
		fine = int(law.get(crime + "_fine", 0))
		newly_wanted = not is_wanted_by(criminal, race_id)
		criminal.wanted[race_id] = int(criminal.wanted.get(race_id, 0)) + fine
	events.append({"type": EVENT_CRIME, "ship_id": criminal.id, "system_id": system.id, "crime": crime,
		"victim_id": victim.id, "victim_name": victim.name, "victim_role": victim.role, "fine": fine,
		"race_id": race_id, "newly_wanted": newly_wanted})


## A pirate was destroyed by `killer` (the player or an NPC ranger): ranking points, and
## karma for the player.
static func pirate_destroyed(killer: ShipData, pirate: ShipData) -> void:
	killer.kills += 1
	killer.points += roundi(pirate.bounty * float(NpcSpawner.settings().get("points_per_bounty", 0.1)))
	if killer.is_player:
		killer.karma += int(settings().get("pirate_karma", 3))


## Why the planet the ship is parked at won't deal with it ("" if it will).
static func refusal(galaxy: GalaxyData, ship: ShipData) -> String:
	var planet := Trade.market_planet(galaxy, ship)
	if planet == null or not is_wanted_by(ship, planet.race_id):
		return ""
	return "%s refuses to deal with you: you are wanted by the %s (fine %d cr). Hail the planet to pay it." % [
		planet.name, GameData.race(planet.race_id).get("name", "?"), int(ship.wanted[planet.race_id])]


## Pays the fine owed to the race of the planet the ship is parked at.
static func pay_fine(ship: ShipData, planet: PlanetData, events: Array[Dictionary]) -> String:
	var fine := int(ship.wanted.get(planet.race_id, 0))
	if fine <= 0:
		return "The %s don't want anything from you." % GameData.race(planet.race_id).get("name", "?")
	if ship.credits < fine:
		return "Your fine is %d cr and you only have %d cr." % [fine, ship.credits]
	ship.credits -= fine
	ship.wanted.erase(planet.race_id)
	events.append({"type": EVENT_FINE_PAID, "ship_id": ship.id, "planet_id": planet.id, "race_id": planet.race_id, "credits": fine})
	return ""


## Once a day: unpaid fines are slowly forgotten and truces run out.
static func daily(galaxy: GalaxyData) -> void:
	var law := settings()
	var decay := float(law.get("fine_decay", 0.02))
	var min_fine := int(law.get("min_fine", 50))
	for ship in galaxy.ships:
		for race_id: String in ship.wanted.keys():
			var fine := floori(float(ship.wanted[race_id]) * (1.0 - decay))
			if fine < min_fine:
				ship.wanted.erase(race_id)
			else:
				ship.wanted[race_id] = fine
		for other_id: int in ship.truce.keys():
			ship.truce[other_id] = int(ship.truce[other_id]) - 1
			if int(ship.truce[other_id]) <= 0:
				ship.truce.erase(other_id)
