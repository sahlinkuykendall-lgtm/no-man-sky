extends Node
## Runs the turn cycle. Autoloaded as "TurnManager".
##
## Solo: the player presses End Turn whenever they like.
## Multiplayer (Milestone 12): a 60 s planning timer, and the turn resolves early once
## every active player is Ready. Orders already flow through submit_order(), which is
## what the server will receive from clients.

## How long the "everything moves at once" animation plays, in seconds.
const RESOLVE_ANIMATION_TIME := 0.9
## Auto-advance plays turns faster.
const AUTO_ANIMATION_TIME := 0.35

var is_resolving: bool = false
## When on, turns keep ending by themselves until the player's ship arrives somewhere.
var auto_advance: bool = false


## Gives the player's ship an order. Returns true if it was accepted.
func submit_order(order: Dictionary) -> bool:
	var ship := GameState.player_ship()
	if ship == null:
		return false
	var error := TurnResolver.apply_order(GameState.galaxy, ship, order)
	if error != "":
		EventBus.message_posted.emit(error, "warning")
		return false
	EventBus.player_order_changed.emit()
	return true


func animation_time() -> float:
	return AUTO_ANIMATION_TIME if auto_advance else RESOLVE_ANIMATION_TIME


func end_turn() -> void:
	if is_resolving or not GameState.has_game():
		return
	is_resolving = true
	EventBus.turn_resolving.emit()
	var events := TurnResolver.resolve_turn(GameState.galaxy)
	EventBus.turn_resolved.emit(GameState.galaxy.day, events)
	await get_tree().create_timer(animation_time()).timeout
	is_resolving = false
	EventBus.turn_ready.emit()
	if auto_advance:
		if _player_is_travelling() and not _has_player_event(events):
			end_turn.call_deferred()
		else:
			set_auto_advance(false)


func set_auto_advance(enabled: bool) -> void:
	auto_advance = enabled
	if enabled and not is_resolving:
		if _player_is_travelling():
			end_turn()
		else:
			auto_advance = false
			EventBus.message_posted.emit("Set a course first, then use Auto to fly until you arrive.", "warning")
	EventBus.player_order_changed.emit()


func _player_is_travelling() -> bool:
	var ship := GameState.player_ship()
	return ship != null and (ship.has_destination or ship.in_hyperspace)


## Auto-advance stops whenever something happens to the player (arrival, jump, ...).
func _has_player_event(events: Array[Dictionary]) -> bool:
	var ship := GameState.player_ship()
	for event in events:
		if event.get("ship_id") == ship.id and event.get("type") != TurnResolver.EVENT_REFUELED:
			return true
	return false
