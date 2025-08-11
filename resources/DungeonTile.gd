# resources/DungeonTile.gd
extends Resource
class_name DungeonTileResource

# Simple constants - no enum complexity
const WALL = 0
const EMPTY = 1
const ENTRANCE = 2
const EXIT = 3
const TREASURE = 4
const MONSTER = 5
const BOSS = 6
const TRAP = 7

@export var tile_type: int = WALL
@export var position: Vector2i = Vector2i.ZERO
@export var visited: bool = false
@export var cleared: bool = false
@export var monster_level: int = 1
@export var monster_count: int = 0
@export var treasure_value: int = 0

func is_passable() -> bool:
	return tile_type != WALL

func get_display_char() -> String:
	match tile_type:
		WALL: return "█"
		EMPTY: return "."
		ENTRANCE: return "S"
		EXIT: return "E"
		TREASURE: return "T"
		MONSTER: return "M"
		BOSS: return "B"
		TRAP: return "X"
		_: return "?"

func get_display_color() -> Color:
	match tile_type:
		WALL: return Color.DIM_GRAY
		EMPTY: return Color.WHITE
		ENTRANCE: return Color.GREEN
		EXIT: return Color.GOLD
		TREASURE: return Color.YELLOW
		MONSTER: return Color.RED
		BOSS: return Color.DARK_RED
		TRAP: return Color.PURPLE
		_: return Color.WHITE
