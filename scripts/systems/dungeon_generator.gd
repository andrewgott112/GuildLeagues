# scripts/systems/dungeon_generator.gd
extends Node
class_name DungeonGenerator

enum GenerationType {
	SIMPLE_ROOMS,
	CELLULAR_AUTOMATA,
	MAZE,
	MIXED
}

var rng: RandomNumberGenerator

func _init():
	rng = RandomNumberGenerator.new()

func generate_dungeon(width: int = 15, height: int = 10, difficulty: int = 1, gen_type: GenerationType = GenerationType.SIMPLE_ROOMS, seed_value: int = 0) -> DungeonResource:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.seed = randi()
	
	var dungeon = DungeonResource.new()
	dungeon.width = width
	dungeon.height = height
	dungeon.difficulty_level = difficulty
	dungeon._initialize_empty_grid()
	
	match gen_type:
		GenerationType.SIMPLE_ROOMS:
			_generate_simple_rooms(dungeon)
		GenerationType.CELLULAR_AUTOMATA:
			_generate_cellular_automata(dungeon)
		GenerationType.MAZE:
			_generate_maze(dungeon)
		GenerationType.MIXED:
			_generate_mixed(dungeon)
	
	_place_special_rooms(dungeon)
	
	return dungeon

func _generate_simple_rooms(dungeon: DungeonResource):
	var rooms = []
	var max_rooms = rng.randi_range(4, 8)
	var attempts = 0
	
	while rooms.size() < max_rooms and attempts < 50:
		var room_width = rng.randi_range(3, 6)
		var room_height = rng.randi_range(3, 5)
		var room_x = rng.randi_range(1, dungeon.width - room_width - 1)
		var room_y = rng.randi_range(1, dungeon.height - room_height - 1)
		
		var new_room = Rect2i(room_x, room_y, room_width, room_height)
		
		var overlaps = false
		for existing_room in rooms:
			if new_room.intersects(existing_room.grow(1)):
				overlaps = true
				break
		
		if not overlaps:
			rooms.append(new_room)
			_carve_room(dungeon, new_room)
		
		attempts += 1
	
	for i in range(1, rooms.size()):
		_connect_rooms(dungeon, rooms[i-1], rooms[i])

func _carve_room(dungeon: DungeonResource, room: Rect2i):
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			var tile = DungeonTileResource.new()
			tile.tile_type = DungeonTileResource.EMPTY
			dungeon.set_tile(x, y, tile)

func _connect_rooms(dungeon: DungeonResource, room1: Rect2i, room2: Rect2i):
	var start = room1.get_center()
	var end = room2.get_center()
	var current = start
	
	while current.x != end.x:
		var tile = DungeonTileResource.new()
		tile.tile_type = DungeonTileResource.EMPTY
		dungeon.set_tile(current.x, current.y, tile)
		current.x += 1 if current.x < end.x else -1
	
	while current.y != end.y:
		var tile = DungeonTileResource.new()
		tile.tile_type = DungeonTileResource.EMPTY
		dungeon.set_tile(current.x, current.y, tile)
		current.y += 1 if current.y < end.y else -1

func _generate_cellular_automata(dungeon: DungeonResource):
	for y in range(1, dungeon.height - 1):
		for x in range(1, dungeon.width - 1):
			if rng.randf() < 0.45:
				var tile = DungeonTileResource.new()
				tile.tile_type = DungeonTileResource.EMPTY
				dungeon.set_tile(x, y, tile)

func _generate_maze(dungeon: DungeonResource):
	# Simple maze - just create some corridors
	for y in range(1, dungeon.height - 1, 2):
		for x in range(1, dungeon.width - 1, 2):
			var tile = DungeonTileResource.new()
			tile.tile_type = DungeonTileResource.EMPTY
			dungeon.set_tile(x, y, tile)

func _generate_mixed(dungeon: DungeonResource):
	_generate_simple_rooms(dungeon)

func _place_special_rooms(dungeon: DungeonResource):
	var empty_tiles = dungeon.find_tiles_of_type(DungeonTileResource.EMPTY)
	if empty_tiles.is_empty():
		return
	
	var placed_objects = []  # Track positions of placed special items
	
	# Place entrance (prefer corner/edge positions)
	var entrance_tile = _find_best_entrance_position(dungeon, empty_tiles)
	if entrance_tile:
		entrance_tile.tile_type = DungeonTileResource.ENTRANCE
		dungeon.entrance_pos = entrance_tile.position
		empty_tiles.erase(entrance_tile)
		placed_objects.append(entrance_tile.position)
	
	# Place exit (far from entrance)
	var exit_tile = _find_farthest_tile_from_positions(empty_tiles, placed_objects, 5.0)
	if exit_tile:
		exit_tile.tile_type = DungeonTileResource.EXIT
		dungeon.exit_pos = exit_tile.position
		empty_tiles.erase(exit_tile)
		placed_objects.append(exit_tile.position)
	
	# Place treasure rooms with good spacing
	var treasure_count = mini(dungeon.max_treasure_rooms, empty_tiles.size() / 4)
	for i in treasure_count:
		if empty_tiles.is_empty():
			break
		
		var treasure_tile = _find_well_spaced_tile(empty_tiles, placed_objects, 4.0)
		if treasure_tile:
			treasure_tile.tile_type = DungeonTileResource.TREASURE
			treasure_tile.treasure_value = rng.randi_range(5, 15) * dungeon.difficulty_level
			empty_tiles.erase(treasure_tile)
			placed_objects.append(treasure_tile.position)
	
	# Place monster rooms with good spacing
	var monster_count = mini(dungeon.max_monster_rooms, empty_tiles.size() / 3)
	for i in monster_count:
		if empty_tiles.is_empty():
			break
		
		var monster_tile = _find_well_spaced_tile(empty_tiles, placed_objects, 3.0)
		if monster_tile:
			monster_tile.tile_type = DungeonTileResource.MONSTER
			monster_tile.monster_level = dungeon.difficulty_level
			monster_tile.monster_count = rng.randi_range(1, 3)
			empty_tiles.erase(monster_tile)
			placed_objects.append(monster_tile.position)

# Helper function to find entrance positions (prefer edges/corners)
func _find_best_entrance_position(dungeon: DungeonResource, empty_tiles: Array):
	var best_tile = null
	var best_score = -1.0
	
	for tile in empty_tiles:
		var score = 0.0
		
		# Prefer edges
		if tile.position.x <= 2 or tile.position.x >= dungeon.width - 3:
			score += 2.0
		if tile.position.y <= 2 or tile.position.y >= dungeon.height - 3:
			score += 2.0
		
		# Prefer corners even more
		if (tile.position.x <= 2 or tile.position.x >= dungeon.width - 3) and \
		   (tile.position.y <= 2 or tile.position.y >= dungeon.height - 3):
			score += 3.0
		
		if score > best_score:
			best_score = score
			best_tile = tile
	
	return best_tile if best_tile else empty_tiles[0]

# Find a tile that's far from all existing placed objects
func _find_well_spaced_tile(empty_tiles: Array, placed_positions: Array, min_distance: float):
	var best_tile = null
	var best_min_distance = 0.0
	var attempts = 0
	var max_attempts = mini(50, empty_tiles.size())
	
	# Try to find a well-spaced tile
	while attempts < max_attempts:
		var candidate = empty_tiles[rng.randi() % empty_tiles.size()]
		var min_dist_to_placed = _get_min_distance_to_positions(candidate.position, placed_positions)
		
		# If this tile is far enough from everything, use it
		if min_dist_to_placed >= min_distance:
			return candidate
		
		# Keep track of the best option in case we can't find ideal spacing
		if min_dist_to_placed > best_min_distance:
			best_min_distance = min_dist_to_placed
			best_tile = candidate
		
		attempts += 1
	
	# If we couldn't find ideal spacing, return the best we found
	return best_tile if best_tile else empty_tiles[rng.randi() % empty_tiles.size()]

# Find the tile farthest from a list of positions
func _find_farthest_tile_from_positions(tiles: Array, positions: Array, min_distance: float = 0.0):
	var farthest_tile = null
	var max_min_distance = -1.0
	
	for tile in tiles:
		var min_dist = _get_min_distance_to_positions(tile.position, positions)
		
		if min_dist > max_min_distance and min_dist >= min_distance:
			max_min_distance = min_dist
			farthest_tile = tile
	
	return farthest_tile if farthest_tile else (tiles[rng.randi() % tiles.size()] if not tiles.is_empty() else null)

# Get the minimum distance from a position to a list of positions
func _get_min_distance_to_positions(pos: Vector2i, positions: Array) -> float:
	if positions.is_empty():
		return INF
	
	var min_distance = INF
	for other_pos in positions:
		var distance = pos.distance_to(Vector2(other_pos))
		min_distance = mini(min_distance, distance)
	
	return min_distance
