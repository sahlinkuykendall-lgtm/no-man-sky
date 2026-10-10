extends Node
## Entry point. Switches between the main menu and the game.

var _menu: MainMenu = null
var _game: Node = null


func _ready() -> void:
	EventBus.return_to_menu_requested.connect(_show_menu)
	_show_menu()


func _show_menu() -> void:
	_free_children()
	TurnManager.auto_advance = false
	GameState.clear()
	_menu = MainMenu.new()
	_menu.new_game_requested.connect(_on_new_game)
	_menu.continue_requested.connect(_on_continue)
	add_child(_menu)


func _on_new_game(galaxy_seed: int, race_id: String) -> void:
	GameState.new_game(galaxy_seed, race_id)
	_start_game()


func _on_continue() -> void:
	if SaveSystem.load_game():
		_start_game()


func _start_game() -> void:
	_free_children()
	_game = Node.new()
	_game.name = "Game"
	_game.add_child(SpaceView.new())
	_game.add_child(Hud.new())
	add_child(_game)


func _free_children() -> void:
	for child in get_children():
		child.queue_free()
	_menu = null
	_game = null
