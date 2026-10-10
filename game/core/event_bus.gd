extends Node
## Global signals so systems can talk without knowing about each other.
## Autoloaded as "EventBus". Emit from anywhere: EventBus.message_posted.emit("Hi")

## A new galaxy was created or loaded; views should rebuild.
signal galaxy_loaded

## The turn is about to resolve (views snapshot positions so they can animate).
signal turn_resolving
## The turn resolved. `events` is the list returned by TurnResolver.resolve_turn().
signal turn_resolved(day: int, events: Array[Dictionary])
## The resolve animation finished; players may give orders again.
signal turn_ready

## The player's orders changed (new course, stop, etc.).
signal player_order_changed

## The player selected something. kind: "planet", "star", "ship" or "" (nothing).
signal selection_changed(kind: String, id: int)

## A message for the in-game log. level: "info", "good", "warning".
signal message_posted(text: String, level: String)

## Ask the game to go back to the main menu.
signal return_to_menu_requested
