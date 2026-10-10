class_name PlanetData
extends RefCounted
## One planet orbiting a star. Positions are in "system units" with the star at (0, 0).

var id: int = 0
var name: String = ""
var type_id: String = ""
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0 ## Radians.
var orbit_speed: float = 0.0 ## Radians per day. Negative = clockwise.
var radius: float = 20.0 ## Size of the planet itself.
var planet_seed: int = 0 ## Used later to generate the surface when landing.

# Only used when inhabited.
var inhabited: bool = false
var race_id: String = ""
var economy_id: String = ""
var government_id: String = ""
var tech_level: int = 0
var population: int = 0 ## Millions.

# Market (only used when inhabited). See Economy for how prices are worked out.
var market_stock: Dictionary = {} ## good id -> units for sale.
var event_id: String = "" ## Current market event ("" = none), e.g. "famine".
var event_days_left: int = 0


func position() -> Vector2:
	return position_at_angle(orbit_angle)


func position_at_angle(angle: float) -> Vector2:
	return Vector2.from_angle(angle) * orbit_radius


## Moves the planet along its orbit.
func advance(days: int = 1) -> void:
	orbit_angle = wrapf(orbit_angle + orbit_speed * days, 0.0, TAU)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"type_id": type_id,
		"orbit_radius": orbit_radius,
		"orbit_angle": orbit_angle,
		"orbit_speed": orbit_speed,
		"radius": radius,
		"planet_seed": planet_seed,
		"inhabited": inhabited,
		"race_id": race_id,
		"economy_id": economy_id,
		"government_id": government_id,
		"tech_level": tech_level,
		"population": population,
		"market_stock": market_stock.duplicate(),
		"event_id": event_id,
		"event_days_left": event_days_left,
	}


static func from_dict(d: Dictionary) -> PlanetData:
	var p := PlanetData.new()
	p.id = int(d.get("id", 0))
	p.name = str(d.get("name", ""))
	p.type_id = str(d.get("type_id", ""))
	p.orbit_radius = float(d.get("orbit_radius", 0.0))
	p.orbit_angle = float(d.get("orbit_angle", 0.0))
	p.orbit_speed = float(d.get("orbit_speed", 0.0))
	p.radius = float(d.get("radius", 20.0))
	p.planet_seed = int(d.get("planet_seed", 0))
	p.inhabited = bool(d.get("inhabited", false))
	p.race_id = str(d.get("race_id", ""))
	p.economy_id = str(d.get("economy_id", ""))
	p.government_id = str(d.get("government_id", ""))
	p.tech_level = int(d.get("tech_level", 0))
	p.population = int(d.get("population", 0))
	var stock: Dictionary = d.get("market_stock", {})
	for good_id: String in stock:
		p.market_stock[good_id] = int(stock[good_id])
	p.event_id = str(d.get("event_id", ""))
	p.event_days_left = int(d.get("event_days_left", 0))
	return p
