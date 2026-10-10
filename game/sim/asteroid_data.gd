class_name AsteroidData
extends RefCounted
## A rock in a system's asteroid belt. Shoot it to break it up into minerals, then pick
## them up with a gripper. Broken asteroids come back after a while (new rocks drift in).

var id: int = 0
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0 ## Radians.
var orbit_speed: float = 0.0 ## Radians per day.
var size: float = 8.0 ## Radius in system units.
var hp: float = 40.0 ## 0 = broken up (waiting to respawn).
var hp_max: float = 40.0
var minerals: int = 5 ## Units of minerals it breaks into.
var respawn_days: int = 0 ## Days until a broken asteroid is back.


func exists() -> bool:
	return hp > 0.0


func position() -> Vector2:
	return position_at_angle(orbit_angle)


func position_at_angle(angle: float) -> Vector2:
	return Vector2.from_angle(angle) * orbit_radius


func advance(days: int = 1) -> void:
	orbit_angle = wrapf(orbit_angle + orbit_speed * days, 0.0, TAU)


func to_dict() -> Dictionary:
	return {
		"id": id,
		"orbit_radius": orbit_radius,
		"orbit_angle": orbit_angle,
		"orbit_speed": orbit_speed,
		"size": size,
		"hp": hp,
		"hp_max": hp_max,
		"minerals": minerals,
		"respawn_days": respawn_days,
	}


static func from_dict(d: Dictionary) -> AsteroidData:
	var a := AsteroidData.new()
	a.id = int(d.get("id", 0))
	a.orbit_radius = float(d.get("orbit_radius", 0.0))
	a.orbit_angle = float(d.get("orbit_angle", 0.0))
	a.orbit_speed = float(d.get("orbit_speed", 0.0))
	a.size = float(d.get("size", 8.0))
	a.hp = float(d.get("hp", 40.0))
	a.hp_max = float(d.get("hp_max", 40.0))
	a.minerals = int(d.get("minerals", 5))
	a.respawn_days = int(d.get("respawn_days", 0))
	return a
