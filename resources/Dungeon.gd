# resources/Dungeon.gd
extends Resource
class_name DungeonResource

@export var name: String = "Unnamed Dungeon"
@export var width: int = 15
@export var height: int = 10
@export var difficulty_level: int = 1
@export var max_treasure_rooms: int = 3
@export var max_monster_rooms: int = 8
@export var entrance_pos: Vector2i = Vector2i.ZERO
@export var exit_pos: Vector2i = Vector2i.ZERO
@export var tiles: Array = []

func _init():
	_initialize_empty_grid()

func _initialize_empty_grid():
	tiles.clear()
	tiles.resize(width * height)
	
	for y in height:
		for x in width:
			var tile = DungeonTileResource.new()
			tile.position = Vector2i(x, y)
			tile.tile_type = DungeonTileResource.WALL
			set_tile(x, y, tile)

func get_tile(x: int, y: int):
	if not is_valid_pos(x, y):
		return null
	return tiles[y * width + x]

func set_tile(x: int, y: int, tile):
	if not is_valid_pos(x, y):
		return
	tile.position = Vector2i(x, y)
	tiles[y * width + x] = tile

func is_valid_pos(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height

func get_neighbors(x: int, y: int) -> Array:
	var neighbors = []
	var directions = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	
	for dir in directions:
		var new_x = x + dir.x
		var new_y = y + dir.y
		var tile = get_tile(new_x, new_y)
		if tile != null:
			neighbors.append(tile)
	
	return neighbors

func get_passable_neighbors(x: int, y: int) -> Array:
	var passable = []
	for neighbor in get_neighbors(x, y):
		if neighbor.is_passable():
			passable.append(neighbor)
	return passable

func find_tiles_of_type(tile_type: int) -> Array:
	var found = []
	for tile in tiles:
		if tile.tile_type == tile_type:
			found.append(tile)
	return found

func get_all_room_tiles() -> Array:
	var rooms = []
	for tile in tiles:
		if tile.tile_type != DungeonTileResource.WALL:
			rooms.append(tile)
	return rooms

func to_ascii() -> String:
	var result = ""
	for y in height:
		for x in width:
			var tile = get_tile(x, y)
			result += tile.get_display_char() if tile else "?"
		result += "\n"
	return result

func count_tiles_of_type(tile_type: int) -> int:
	var count = 0
	for tile in tiles:
		if tile.tile_type == tile_type:
			count += 1
	return count
