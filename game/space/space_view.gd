class_name SpaceView
extends Node3D
## Shows the player's current star system in a tilted top-down ("isometric") 3D view.
##
## It only READS the simulation (GameState.galaxy) and sends the player's clicks to
## TurnManager as orders. It never changes the simulation directly.
##
## Coordinates: the simulation is 2D (x, y). In 3D that becomes (x, 0, y) * WORLD_SCALE,
## so the flat "space plane" is the XZ plane and +y in the simulation points down the screen.
##
## Controls: left click = fly to point / planet, right-drag or WASD = move camera,
## mouse wheel = zoom, F = center on your ship.

const WORLD_SCALE := 0.05 ## Simulation units -> 3D units.
const CAMERA_PITCH_DEG := -62.0
const ZOOM_MIN := 12.0
const ZOOM_MAX := 170.0
const KEY_PAN_SPEED := 0.9 ## Screen-heights per second.
const LABEL_SCALE := 0.00042 ## Label size relative to the zoom, so text stays readable.
const SHIP_PICK_RADIUS := 30.0 ## Simulation units.

const COLOR_ORBIT := Color(0.35, 0.45, 0.7, 0.35)
const COLOR_BOUNDARY := Color(0.65, 0.35, 0.95, 0.4)
const COLOR_COURSE := Color(0.45, 1.0, 0.6, 0.9)
const COLOR_JUMP_COURSE := Color(0.75, 0.5, 1.0, 0.9)
const COLOR_SELECTION := Color(1.0, 0.9, 0.35)
const COLOR_PLAYER := Color(0.7, 0.95, 1.0)

var _camera_pivot: Node3D
var _camera: Camera3D
var _environment: Environment
var _starfield: MultiMeshInstance3D
var _system_root: Node3D ## Everything belonging to the current system; rebuilt on system change.

var _system_id: int = -1
var _showing_hyperspace: bool = false
var _planet_nodes: Dictionary = {} ## planet id -> Node3D
var _ship_nodes: Dictionary = {} ## ship id -> Node3D
var _labels: Array[Label3D] = []
var _label_offsets: Dictionary = {} ## Label3D -> base offset (3D units below its object)

var _course_mesh: ImmediateMesh
var _destination_marker: MeshInstance3D
var _days_label: Label3D
var _selection_ring: MeshInstance3D
var _selection_kind: String = ""
var _selection_id: int = -1

# Turn animation: where things were before the turn resolved.
var _animating: bool = false
var _anim_elapsed: float = 0.0
var _from_planet_angles: Dictionary = {} ## planet id -> angle
var _from_ships: Dictionary = {} ## ship id -> {"position", "heading", "orbiting"}

var _dragging: bool = false


func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_starfield()
	_build_course_visuals()
	EventBus.galaxy_loaded.connect(_rebuild)
	EventBus.turn_resolving.connect(_on_turn_resolving)
	EventBus.turn_resolved.connect(_on_turn_resolved)
	EventBus.selection_changed.connect(_on_selection_changed)
	_rebuild()


# --- Coordinate helpers -------------------------------------------------------

static func to_world(sim_position: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(sim_position.x * WORLD_SCALE, height, sim_position.y * WORLD_SCALE)


static func to_sim(world_position: Vector3) -> Vector2:
	return Vector2(world_position.x, world_position.z) / WORLD_SCALE


## Converts the sim heading (radians) to a Y rotation for a node that faces -Z.
static func heading_to_rotation(heading: float) -> float:
	return atan2(-cos(heading), -sin(heading))


# --- Building the scene -------------------------------------------------------

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = Color(0.012, 0.016, 0.04)
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = Color(0.35, 0.4, 0.6)
	_environment.ambient_light_energy = 0.35
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.9
	_environment.glow_bloom = 0.15
	_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = _environment
	add_child(world_env)


func _build_camera() -> void:
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	_camera_pivot.rotation_degrees = Vector3(CAMERA_PITCH_DEG, 0.0, 0.0)
	add_child(_camera_pivot)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 60.0
	_camera.near = 1.0
	_camera.far = 800.0
	_camera.position = Vector3(0.0, 0.0, 300.0)
	_camera_pivot.add_child(_camera)
	_camera.make_current()


func _build_starfield() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var star_mesh := SphereMesh.new()
	star_mesh.radius = 0.12
	star_mesh.height = 0.24
	star_mesh.radial_segments = 4
	star_mesh.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	star_mesh.material = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = star_mesh
	multimesh.instance_count = 2500
	for i in multimesh.instance_count:
		var star_position := Vector3(rng.randf_range(-450.0, 450.0), rng.randf_range(-140.0, -60.0), rng.randf_range(-450.0, 450.0))
		var size := rng.randf_range(0.6, 2.2)
		multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * size), star_position))
		var brightness := rng.randf_range(0.3, 1.0)
		var tint := Color(0.8, 0.85, 1.0).lerp(Color(1.0, 0.85, 0.7), rng.randf())
		multimesh.set_instance_color(i, tint * brightness)
	_starfield = MultiMeshInstance3D.new()
	_starfield.multimesh = multimesh
	add_child(_starfield)


func _build_course_visuals() -> void:
	_course_mesh = ImmediateMesh.new()
	var course := MeshInstance3D.new()
	course.mesh = _course_mesh
	course.material_override = _line_material()
	add_child(course)

	_destination_marker = _make_ring(0.55, 0.7, COLOR_COURSE)
	_destination_marker.visible = false
	add_child(_destination_marker)

	_days_label = _make_label("", COLOR_COURSE, 0.0)
	add_child(_days_label)

	_selection_ring = _make_ring(1.0, 1.12, COLOR_SELECTION)
	_selection_ring.visible = false
	add_child(_selection_ring)


func _rebuild() -> void:
	if _system_root:
		_system_root.queue_free()
	_system_root = Node3D.new()
	_system_root.name = "System"
	add_child(_system_root)
	_planet_nodes.clear()
	_ship_nodes.clear()
	_forget_old_labels()
	_animating = false
	_on_selection_changed("", -1)

	var ship := GameState.player_ship()
	if ship == null:
		return
	_showing_hyperspace = ship.in_hyperspace
	_environment.background_color = Color(0.025, 0.005, 0.045) if _showing_hyperspace else Color(0.012, 0.016, 0.04)
	if _showing_hyperspace:
		_system_id = -1
		return

	_system_id = ship.system_id
	var system := GameState.galaxy.get_system(_system_id)
	_build_star(system)
	for planet in system.planets:
		_build_planet(planet)
	_build_circle(system.jump_radius, COLOR_BOUNDARY, true)
	_sync_ship_nodes()
	_apply_animation(1.0)
	_camera_pivot.position = to_world(ship.position)
	_camera.size = clampf(system.jump_radius * WORLD_SCALE * 1.15, ZOOM_MIN, ZOOM_MAX)


func _build_star(system: StarSystemData) -> void:
	var star_type := GameData.star_type(system.star_type_id)
	var color := Color(star_type.get("color", "#ffd76a"))
	var radius := system.star_radius() * WORLD_SCALE

	var star := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	star.mesh = mesh
	_system_root.add_child(star)

	var light := OmniLight3D.new()
	light.light_color = color.lerp(Color.WHITE, 0.6)
	light.light_energy = 1.6
	light.omni_range = system.jump_radius * WORLD_SCALE * 2.0
	light.omni_attenuation = 0.0
	_system_root.add_child(light)

	_add_label(_system_root, system.name, color, Vector3.ZERO, radius + 0.6)


func _build_planet(planet: PlanetData) -> void:
	var holder := Node3D.new()
	_system_root.add_child(holder)
	_planet_nodes[planet.id] = holder

	var planet_type := GameData.planet_type(planet.type_id)
	var radius := planet.radius * WORLD_SCALE
	var body := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 20
	mesh.rings = 10
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(planet_type.get("color", "#888888"))
	material.roughness = 0.9
	mesh.material = material
	body.mesh = mesh
	holder.add_child(body)

	var label_color := Color(0.8, 0.85, 0.95)
	if planet.inhabited:
		label_color = Color(GameData.race(planet.race_id).get("color", "#ffffff"))
		var ring := _make_ring(radius * 1.35, radius * 1.5, label_color)
		holder.add_child(ring)
	_add_label(holder, planet.name, label_color, Vector3.ZERO, radius + 0.5)
	_build_circle(planet.orbit_radius, COLOR_ORBIT, false)


func _build_circle(sim_radius: float, color: Color, dashed: bool) -> void:
	var mesh := ImmediateMesh.new()
	var segments := 128
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in segments:
		if dashed and i % 2 == 1:
			continue
		var a := Vector2.from_angle(TAU * i / segments) * sim_radius
		var b := Vector2.from_angle(TAU * (i + 1) / segments) * sim_radius
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(to_world(a))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(to_world(b))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _line_material()
	_system_root.add_child(instance)


func _make_ship_node(ship: ShipData) -> Node3D:
	var holder := Node3D.new()
	var color := COLOR_PLAYER if ship.is_player else Color(GameData.race(ship.race_id).get("color", "#cccccc"))
	var length := 1.5 if ship.is_player else 1.0

	var hull := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(length * 0.7, length, length * 0.22)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.5
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.25
	prism.material = material
	hull.mesh = prism
	hull.rotation_degrees = Vector3(-90.0, 0.0, 0.0) # Point the prism tip forward (-Z).
	holder.add_child(hull)

	var engine := MeshInstance3D.new()
	var glow := SphereMesh.new()
	glow.radius = length * 0.14
	glow.height = length * 0.28
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.albedo_color = Color(0.5, 0.8, 1.0)
	glow_material.emission_enabled = true
	glow_material.emission = Color(0.5, 0.8, 1.0)
	glow_material.emission_energy_multiplier = 4.0
	glow.material = glow_material
	engine.mesh = glow
	engine.position = Vector3(0.0, 0.0, length * 0.5)
	holder.add_child(engine)

	if ship.is_player:
		_add_label(holder, "You", COLOR_PLAYER, Vector3.ZERO, 0.9)
	return holder


func _make_ring(inner: float, outer: float, color: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = outer
	torus.rings = 48
	torus.ring_segments = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color, 0.8)
	torus.material = material
	ring.mesh = torus
	return ring


func _make_label(text: String, color: Color, offset: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.font_size = 36
	label.outline_size = 10
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.render_priority = 10
	_labels.append(label)
	_label_offsets[label] = offset
	return label


## Drops labels that belonged to the previous system (they are being freed).
func _forget_old_labels() -> void:
	var kept: Array[Label3D] = []
	for label in _labels:
		if is_instance_valid(label) and label.get_parent() == self:
			kept.append(label)
	_labels = kept
	for key: Variant in _label_offsets.keys():
		if not is_instance_valid(key) or not kept.has(key):
			_label_offsets.erase(key)


func _add_label(parent: Node3D, text: String, color: Color, at: Vector3, offset: float) -> void:
	var label := _make_label(text, color, offset)
	label.position = at
	parent.add_child(label)


func _line_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


# --- Keeping visuals in sync with the simulation --------------------------------

## Creates nodes for ships that appeared in this system and removes ones that left.
func _sync_ship_nodes() -> void:
	var present := {}
	for ship in GameState.galaxy.ships_in_system(_system_id):
		present[ship.id] = true
		if not _ship_nodes.has(ship.id):
			var node := _make_ship_node(ship)
			_system_root.add_child(node)
			_ship_nodes[ship.id] = node
	for ship_id: int in _ship_nodes.keys():
		if not present.has(ship_id):
			_ship_nodes[ship_id].queue_free()
			_ship_nodes.erase(ship_id)


func _on_turn_resolving() -> void:
	_from_planet_angles.clear()
	_from_ships.clear()
	if _system_id < 0:
		return
	for planet in GameState.galaxy.get_system(_system_id).planets:
		_from_planet_angles[planet.id] = planet.orbit_angle
	for ship in GameState.galaxy.ships_in_system(_system_id):
		_from_ships[ship.id] = {"position": ship.position, "heading": ship.heading, "orbiting": ship.orbiting_planet_id}


func _on_turn_resolved(_day: int, _events: Array[Dictionary]) -> void:
	var ship := GameState.player_ship()
	if ship.in_hyperspace != _showing_hyperspace or (not ship.in_hyperspace and ship.system_id != _system_id):
		_rebuild()
		return
	if _showing_hyperspace:
		return
	_sync_ship_nodes()
	_anim_elapsed = 0.0
	_animating = true


## Positions every planet and ship. t = 0 is the start of the turn, 1 is the end.
func _apply_animation(t: float) -> void:
	if _system_id < 0:
		return
	var system := GameState.galaxy.get_system(_system_id)
	var planet_positions := {}
	for planet in system.planets:
		var angle := planet.orbit_angle
		if t < 1.0 and _from_planet_angles.has(planet.id):
			angle = lerp_angle(_from_planet_angles[planet.id], planet.orbit_angle, t)
		planet_positions[planet.id] = planet.position_at_angle(angle)
		_planet_nodes[planet.id].position = to_world(planet_positions[planet.id])

	for ship in GameState.galaxy.ships_in_system(_system_id):
		if not _ship_nodes.has(ship.id):
			continue
		var ship_position := ship.position
		var heading := ship.heading
		if t < 1.0 and _from_ships.has(ship.id):
			var from: Dictionary = _from_ships[ship.id]
			if from["orbiting"] >= 0 and from["orbiting"] == ship.orbiting_planet_id:
				ship_position = planet_positions[ship.orbiting_planet_id] + ship.orbit_offset
			else:
				ship_position = (from["position"] as Vector2).lerp(ship.position, t)
			heading = lerp_angle(from["heading"], ship.heading, minf(t * 3.0, 1.0))
		var node: Node3D = _ship_nodes[ship.id]
		node.position = to_world(ship_position, 0.3)
		node.rotation.y = heading_to_rotation(heading)


func _process(delta: float) -> void:
	_pan_with_keys(delta)
	if _showing_hyperspace:
		_starfield.position.z = fmod(_starfield.position.z + delta * 120.0, 300.0)
	else:
		_starfield.position.z = 0.0
	if _animating:
		_anim_elapsed += delta
		var t := clampf(_anim_elapsed / TurnManager.animation_time(), 0.0, 1.0)
		_apply_animation(smoothstep(0.0, 1.0, t))
		if t >= 1.0:
			_animating = false
	_update_course()
	_update_selection_ring()
	_update_labels()


func _update_course() -> void:
	_course_mesh.clear_surfaces()
	_destination_marker.visible = false
	_days_label.visible = false
	var ship := GameState.player_ship()
	if ship == null or _showing_hyperspace or not ship.has_destination or not _ship_nodes.has(ship.id):
		return
	var from: Vector3 = _ship_nodes[ship.id].position
	from.y = 0.0
	var to := to_world(ship.destination)
	var color := COLOR_COURSE
	if ship.target_planet_id >= 0 and _planet_nodes.has(ship.target_planet_id):
		to = _planet_nodes[ship.target_planet_id].position
	elif ship.jump_target_system_id >= 0:
		to = to_world(TurnResolver.jump_exit_point(GameState.galaxy, ship))
		color = COLOR_JUMP_COURSE

	# Dashed line.
	var length := from.distance_to(to)
	if length > 0.01:
		var dash := maxf(_camera.size * 0.012, 0.2)
		var steps := mini(int(length / dash), 400)
		_course_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for i in range(0, steps, 2):
			_course_mesh.surface_set_color(color)
			_course_mesh.surface_add_vertex(from.lerp(to, float(i) / steps))
			_course_mesh.surface_set_color(color)
			_course_mesh.surface_add_vertex(from.lerp(to, float(i + 1) / steps))
		_course_mesh.surface_end()

	_destination_marker.visible = ship.target_planet_id < 0
	_destination_marker.position = to
	var days := TurnResolver.days_to_destination(GameState.galaxy, ship)
	var text := "%d day%s" % [days, "" if days == 1 else "s"]
	if ship.jump_target_system_id >= 0:
		text = "Jump to %s: %s to boundary" % [GameState.galaxy.get_system(ship.jump_target_system_id).name, text]
	_days_label.text = text
	_days_label.modulate = color
	_days_label.position = to + Vector3(0.0, 0.0, -_camera.size * 0.035)
	_days_label.visible = true


func _update_selection_ring() -> void:
	var target: Node3D = null
	var size := 1.0
	if _selection_kind == "planet" and _planet_nodes.has(_selection_id):
		target = _planet_nodes[_selection_id]
		size = GameState.current_system().get_planet(_selection_id).radius * WORLD_SCALE * 1.8
	elif _selection_kind == "ship" and _ship_nodes.has(_selection_id):
		target = _ship_nodes[_selection_id]
		size = 1.2
	elif _selection_kind == "star" and _system_id >= 0:
		size = GameState.current_system().star_radius() * WORLD_SCALE * 1.4
		_selection_ring.position = Vector3.ZERO
		_selection_ring.scale = Vector3.ONE * size
		_selection_ring.visible = true
		return
	_selection_ring.visible = target != null
	if target:
		_selection_ring.position = Vector3(target.position.x, 0.0, target.position.z)
		_selection_ring.scale = Vector3.ONE * size


## Keeps text the same size on screen at every zoom level.
func _update_labels() -> void:
	var pixel_size := _camera.size * LABEL_SCALE
	for label in _labels:
		if not is_instance_valid(label):
			continue
		label.pixel_size = pixel_size
		if _label_offsets.has(label) and label != _days_label:
			var offset: float = _label_offsets[label]
			# Undo the parent's rotation (ships turn) so the text always sits below its object.
			var parent_basis := (label.get_parent() as Node3D).basis
			label.position = parent_basis.inverse() * Vector3(0.0, 0.0, offset + _camera.size * 0.022)


func _on_selection_changed(kind: String, id: int) -> void:
	_selection_kind = kind
	_selection_id = id


# --- Input ----------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom(0.88)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom(1.0 / 0.88)
		elif button.button_index == MOUSE_BUTTON_RIGHT or button.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = button.pressed
		elif button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_on_left_click(button.position)
	elif event is InputEventMouseMotion and _dragging:
		_pan_pixels((event as InputEventMouseMotion).relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F:
			_center_on_player()


func _zoom(factor: float) -> void:
	_camera.size = clampf(_camera.size * factor, ZOOM_MIN, ZOOM_MAX)


func _pan_pixels(relative: Vector2) -> void:
	var units_per_pixel := _camera.size / get_viewport().get_visible_rect().size.y
	var pitch := absf(deg_to_rad(CAMERA_PITCH_DEG))
	_camera_pivot.position.x -= relative.x * units_per_pixel
	_camera_pivot.position.z -= relative.y * units_per_pixel / sin(pitch)


func _pan_with_keys(delta: float) -> void:
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		direction.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		direction.x -= 1.0
	if direction != Vector2.ZERO:
		var pixels := get_viewport().get_visible_rect().size.y * KEY_PAN_SPEED * delta
		_pan_pixels(direction * pixels)


func _center_on_player() -> void:
	var ship := GameState.player_ship()
	if ship and _ship_nodes.has(ship.id):
		var node: Node3D = _ship_nodes[ship.id]
		_camera_pivot.position = Vector3(node.position.x, 0.0, node.position.z)


func _screen_to_sim(screen_position: Vector2) -> Variant:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, direction)
	if hit == null:
		return null
	return to_sim(hit)


func _on_left_click(screen_position: Vector2) -> void:
	if _showing_hyperspace or _system_id < 0:
		return
	var hit: Variant = _screen_to_sim(screen_position)
	if hit == null:
		return
	var point: Vector2 = hit
	var system := GameState.galaxy.get_system(_system_id)
	var pick_slack := _camera.size / WORLD_SCALE * 0.012 # Easier to click when zoomed out.

	# Ships first (they are small), then planets, then the star, else empty space.
	for ship in GameState.galaxy.ships_in_system(_system_id):
		if _ship_nodes.has(ship.id) and to_sim(_ship_nodes[ship.id].position).distance_to(point) < SHIP_PICK_RADIUS + pick_slack:
			if not ship.is_player:
				EventBus.selection_changed.emit("ship", ship.id)
				return
	for planet in system.planets:
		if to_sim(_planet_nodes[planet.id].position).distance_to(point) < planet.radius + pick_slack:
			EventBus.selection_changed.emit("planet", planet.id)
			TurnManager.submit_order({"type": "move_to_planet", "planet_id": planet.id})
			return
	if point.length() < system.star_radius() + pick_slack:
		EventBus.selection_changed.emit("star", _system_id)
		return
	EventBus.selection_changed.emit("", -1)
	TurnManager.submit_order({"type": "move_to_point", "point": point})
