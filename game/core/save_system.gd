extends Node
## Saves and loads the galaxy as JSON. Autoloaded as "SaveSystem".
## Files live in user://saves/ (on Windows: %APPDATA%/Godot/app_userdata/Project Ranger/saves).

const SAVE_DIR := "user://saves/"
const DEFAULT_SLOT := "quicksave"


func save_path(slot: String = DEFAULT_SLOT) -> String:
	return SAVE_DIR + slot + ".json"


func has_save(slot: String = DEFAULT_SLOT) -> bool:
	return FileAccess.file_exists(save_path(slot))


func save_game(slot: String = DEFAULT_SLOT) -> bool:
	if not GameState.has_game():
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		EventBus.message_posted.emit("Could not save the game.", "warning")
		return false
	file.store_string(JSON.stringify(GameState.galaxy.to_dict(), "\t", false, true))
	file.close()
	EventBus.message_posted.emit("Game saved.", "good")
	return true


func load_game(slot: String = DEFAULT_SLOT) -> bool:
	if not has_save(slot):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if not data is Dictionary:
		push_error("SaveSystem: save file is damaged: %s" % save_path(slot))
		return false
	if int(data.get("save_version", 0)) > GalaxyData.SAVE_VERSION:
		push_error("SaveSystem: save was made by a newer version of the game.")
		return false
	GameState.set_galaxy(GalaxyData.from_dict(data))
	EventBus.message_posted.emit("Game loaded.", "good")
	return true
