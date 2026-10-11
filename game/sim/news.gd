class_name News
extends RefCounted
## The Galactic News Network: short headlines about what happens around the galaxy
## (market events, pirates destroyed, traders lost, crimes). Pure logic. The newest
## headline comes first in GalaxyData.news.

const MAX_ITEMS := 40


static func add(galaxy: GalaxyData, text: String) -> void:
	galaxy.news.push_front({"day": galaxy.day, "text": text})
	if galaxy.news.size() > MAX_ITEMS:
		galaxy.news.resize(MAX_ITEMS)


## Turns the interesting events of a turn into headlines. Pirates destroyed by the player or
## rangers get their own headline; the police's daily catch is summed up in one.
static func record(galaxy: GalaxyData, events: Array[Dictionary]) -> void:
	var police_kills := 0
	for event in events:
		match event["type"]:
			Economy.EVENT_MARKET_EVENT:
				var system := galaxy.get_system(event["system_id"])
				var planet := system.get_planet(event["planet_id"])
				var market_event := GameData.market_event(event["event_id"])
				add(galaxy, str(market_event.get("news", "Strange events on %s.")) % ("%s (%s)" % [planet.name, system.name]))
			Combat.EVENT_SHIP_DESTROYED:
				var system_name := galaxy.get_system(event["system_id"]).name
				if event["role"] == ShipData.ROLE_PIRATE and event["killer_role"] == ShipData.ROLE_POLICE:
					police_kills += 1
				elif event["role"] == ShipData.ROLE_PIRATE and event["killer_role"] != ShipData.ROLE_PIRATE:
					var killer := galaxy.get_ship(event["killer_id"])
					var hero: String = "You" if killer != null and killer.is_player else event["killer_name"]
					add(galaxy, "%s destroyed the pirate %s in the %s system." % [hero, event["name"], system_name])
				elif event["role"] == ShipData.ROLE_TRADER and event["killer_role"] == ShipData.ROLE_PIRATE:
					add(galaxy, "Pirates destroyed the %s in the %s system." % [event["name"], system_name])
			Law.EVENT_CRIME:
				if event["newly_wanted"] or event["crime"] != Law.CRIME_ASSAULT:
					add(galaxy, crime_headline(galaxy, event))
	if police_kills > 0:
		add(galaxy, "Police patrols destroyed %d pirate ship%s across the galaxy." % [police_kills, "" if police_kills == 1 else "s"])


static func crime_headline(galaxy: GalaxyData, event: Dictionary) -> String:
	var criminal := galaxy.get_ship(event["ship_id"])
	var verb: String = {Law.CRIME_ASSAULT: "attacked", Law.CRIME_MURDER: "destroyed", Law.CRIME_EXTORTION: "robbed"}.get(event["crime"], "attacked")
	var system_name := galaxy.get_system(event["system_id"]).name
	var is_you := criminal != null and criminal.is_player
	var who := "You" if is_you else (criminal.name if criminal != null else "A pilot")
	var text := "%s %s the %s in the %s system." % [who, verb, event["victim_name"], system_name]
	if event["race_id"] != "":
		text += " The %s police want %s." % [GameData.race(event["race_id"]).get("adjective", "?"), "you" if is_you else "them"]
	return text
