# scripts/systems/visual_exploration.gd
extends Node
class_name VisualExploration

signal exploration_step_complete(result: Dictionary)
signal exploration_finished(final_result: Dictionary)

enum ExplorationState {
	IDLE,
	EXPLORING,
	PAUSED_FOR_ENCOUNTER,
	FINISHED
}

# Exploration data
var current_state: ExplorationState = ExplorationState.IDLE
var party_position: Vector2i = Vector2i.ZERO
var visited_tiles: Array[Vector2i] = []
var exploration_targets: Array[Vector2i] = []
var current_path: Array[Vector2i] = []
var exploration_progress: Dictionary = {}

# Party stats
var party_navigation: int = 0
var party_strength: int = 0
var moves_made: int = 0
var exploration_efficiency: float = 0.0

# References
var dungeon: DungeonResource
var party: Array
var rng: RandomNumberGenerator

func _init():
	rng = RandomNumberGenerator.new()
	rng.randomize()

func start_exploration(dungeon_ref: DungeonResource, party_ref: Array) -> bool:
	if current_state != ExplorationState.IDLE:
		return false
	
	dungeon = dungeon_ref
	party = party_ref
	
	# Calculate party stats
	party_navigation = _calculate_navigation_skill(party)
	party_strength = _calculate_party_strength(party)
	
	# Find entrance
	var entrance_tiles = dungeon.find_tiles_of_type(DungeonTileResource.ENTRANCE)
	if entrance_tiles.is_empty():
		# If no entrance, start at first empty tile
		var empty_tiles = dungeon.find_tiles_of_type(DungeonTileResource.EMPTY)
		if empty_tiles.is_empty():
			return false
		party_position = empty_tiles[0].position
	else:
		party_position = entrance_tiles[0].position
	
	# Initialize exploration
	visited_tiles.clear()
	exploration_targets.clear()
	current_path.clear()
	moves_made = 0
	
	visited_tiles.append(party_position)
	_discover_nearby_targets()
	
	current_state = ExplorationState.EXPLORING
	exploration_progress = _create_step_result("Started exploration at entrance")
	
	return true

func get_party_position() -> Vector2i:
	return party_position

func get_visited_tiles() -> Array[Vector2i]:
	return visited_tiles.duplicate()

func is_exploring() -> bool:
	return current_state == ExplorationState.EXPLORING

func is_finished() -> bool:
	return current_state == ExplorationState.FINISHED

# Execute one step of exploration
func step_exploration() -> Dictionary:
	if current_state != ExplorationState.EXPLORING:
		return exploration_progress
	
	# Check if we have a path to follow
	if current_path.is_empty():
		print("No current path, finding next destination...")
		_find_next_destination()
	
	# If still no path, exploration might be done
	if current_path.is_empty():
		print("No path found - finishing exploration")
		print("Current position: (%d, %d)" % [party_position.x, party_position.y])
		print("Visited tiles: %d" % visited_tiles.size())
		print("Available targets: %d" % exploration_targets.size())
		_finish_exploration()
		return exploration_progress
	
	# Move to next position in path
	var next_pos = current_path.pop_front()
	party_position = next_pos
	moves_made += 1

	# 🔧 NEW: don't let the current tile remain a target
	if party_position in exploration_targets:
		exploration_targets.erase(party_position)

	if party_position not in visited_tiles:
		visited_tiles.append(party_position)

	# Check what's at this position
	var tile = dungeon.get_tile(party_position.x, party_position.y)
	var step_result = _process_tile_encounter(tile)
	
	# Discover new targets based on navigation skill
	_discover_nearby_targets()
	
	exploration_progress = step_result
	exploration_step_complete.emit(step_result)
	
	# Continue exploring regardless of what we encountered
	# All encounters (treasure, monsters, etc.) are handled automatically
	return step_result

func _calculate_navigation_skill(party_data: Array) -> int:
	var total_navigation = 0
	var navigator_bonus = 0
	
	for adventurer in party_data:
		if adventurer.role and str(adventurer.role.role_stat_name).to_lower() in ["navigation", "navigate"]:
			total_navigation += adventurer.role_stat * 2
			navigator_bonus += 5
		else:
			total_navigation += max(1, adventurer.role_stat / 2)
	
	return total_navigation + navigator_bonus + party_data.size() * 2

func _calculate_party_strength(party_data: Array) -> int:
	var total_strength = 0
	for adventurer in party_data:
		total_strength += adventurer.attack + adventurer.defense + (adventurer.hp / 5)
	return total_strength

func _discover_nearby_targets():
	# Navigation skill determines how far the party can "see" potential targets
	var vision_range = 2 + (party_navigation / 20)  # 2-5 tiles range
	
	# Find interesting tiles within range
	for y in range(party_position.y - vision_range, party_position.y + vision_range + 1):
		for x in range(party_position.x - vision_range, party_position.x + vision_range + 1):
			if not dungeon.is_valid_pos(x, y):
				continue
			
			var pos = Vector2i(x, y)
			if pos == party_position or pos in visited_tiles:
				continue
			
			var tile = dungeon.get_tile(x, y)
			if not tile or not tile.is_passable():
				continue
			
			# Add interesting tiles to targets
			if tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.MONSTER, DungeonTileResource.EXIT]:
				if pos not in exploration_targets:
					exploration_targets.append(pos)
			elif tile.tile_type == DungeonTileResource.EMPTY:
				# Add empty rooms for general exploration (more likely now)
				if rng.randf() < 0.7 and pos not in exploration_targets:  # Increased from 0.3 to 0.7
					exploration_targets.append(pos)
	
	# If we still don't have many targets, be more aggressive
	if exploration_targets.size() < 3:
		print("Low target count (%d), expanding search..." % exploration_targets.size())
		_expand_target_search()

func _find_next_destination():
	current_path.clear()
	print("Finding next destination from (%d, %d)" % [party_position.x, party_position.y])
	
	if exploration_targets.is_empty():
		print("No targets available, searching for unexplored areas...")
		# No specific targets, try to find unexplored areas
		_find_unexplored_areas()
	
	if exploration_targets.is_empty():
		print("Still no targets, doing thorough search...")
		# Still nothing, do a more thorough search for ANY unvisited passable tile
		_find_any_unvisited_areas()
	
	if exploration_targets.is_empty():
		print("No unvisited areas found - exploration complete")
		# Truly nothing left, exploration is done
		return
	
	print("Have %d targets available" % exploration_targets.size())
	
	# Choose best target based on navigation skill and priorities
	var best_target = _choose_best_target()
	if best_target == Vector2i(-1, -1):
		print("No valid target chosen")
		return
	
	print("Chosen target: (%d, %d)" % [best_target.x, best_target.y])
	
	# Generate path to target
	current_path = _find_path_to_target(best_target)
	if current_path.is_empty():
		print("Failed to find path to target (%d, %d)" % [best_target.x, best_target.y])
	else:
		print("Found path with %d steps" % current_path.size())
	
	exploration_targets.erase(best_target)

func _find_unexplored_areas():
	# Look for empty tiles that haven't been visited yet
	var empty_tiles = dungeon.find_tiles_of_type(DungeonTileResource.EMPTY)
	
	for tile in empty_tiles:
		if tile.position not in visited_tiles:
			exploration_targets.append(tile.position)
	
	# Also look for special tiles we might have missed
	var special_types = [DungeonTileResource.TREASURE, DungeonTileResource.MONSTER, DungeonTileResource.EXIT, DungeonTileResource.BOSS]
	for tile_type in special_types:
		var special_tiles = dungeon.find_tiles_of_type(tile_type)
		for tile in special_tiles:
			if tile.position not in visited_tiles and tile.position not in exploration_targets:
				exploration_targets.append(tile.position)

func _find_any_unvisited_areas():
	# Last resort: find ANY passable tile we haven't visited
	print("Doing thorough search for unvisited areas...")
	
	for y in dungeon.height:
		for x in dungeon.width:
			var pos = Vector2i(x, y)
			if pos in visited_tiles:
				continue
				
			var tile = dungeon.get_tile(x, y)
			if tile and tile.is_passable():
				exploration_targets.append(pos)
				print("Found unvisited passable tile at (%d, %d)" % [x, y])
	
	print("Total unvisited areas found: %d" % exploration_targets.size())

func _expand_target_search():
	# Expand search radius when we're running low on targets
	var expanded_range = 8  # Look much further out
	
	for y in range(party_position.y - expanded_range, party_position.y + expanded_range + 1):
		for x in range(party_position.x - expanded_range, party_position.x + expanded_range + 1):
			if not dungeon.is_valid_pos(x, y):
				continue
			
			var pos = Vector2i(x, y)
			if pos == party_position or pos in visited_tiles or pos in exploration_targets:
				continue
			
			var tile = dungeon.get_tile(x, y)
			if tile and tile.is_passable():
				exploration_targets.append(pos)
				if exploration_targets.size() >= 10:  # Don't get too many
					break
		if exploration_targets.size() >= 10:
			break
	
	print("After expanded search: %d targets" % exploration_targets.size())

func _choose_best_target() -> Vector2i:
	if exploration_targets.is_empty():
		print("No exploration targets available")
		return Vector2i(-1, -1)

	var best_target := Vector2i(-1, -1)
	var best_score := -1e20
	var valid_targets := 0

	for target in exploration_targets:
		if target == party_position:
			continue  # <-- don't retarget the tile we’re on

		var tile = dungeon.get_tile(target.x, target.y)
		if not tile:
			continue
		
		valid_targets += 1
		var score = 0.0
		var distance = party_position.distance_to(Vector2(target))
		
		# Prioritize by tile type
		match tile.tile_type:
			DungeonTileResource.TREASURE:
				score = 100.0 - distance * 2.0  # High priority
			DungeonTileResource.EXIT:
				score = 80.0 - distance * 1.5   # Medium-high priority
			DungeonTileResource.MONSTER:
				score = 60.0 - distance * 1.0   # Medium priority
			DungeonTileResource.EMPTY:
				score = 30.0 - distance * 3.0   # Low priority, prefer close ones
		
		# Navigation skill affects target selection
		if party_navigation > 30:
			# Good navigators prefer treasures and exits
			if tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.EXIT]:
				score *= 1.5
		
		print("Target (%d, %d): type %d, distance %.1f, score %.1f" % [target.x, target.y, tile.tile_type, distance, score])
		
		if score > best_score:
			best_score = score
			best_target = target
	
	print("Valid targets: %d, Best target: (%d, %d) with score %.1f" % [valid_targets, best_target.x, best_target.y, best_score])
	return best_target

func _find_path_to_target(target: Vector2i) -> Array[Vector2i]:
	print("Finding path from (%d, %d) to (%d, %d)" % [party_position.x, party_position.y, target.x, target.y])
	
	# Simple pathfinding - move towards target step by step
	var path: Array[Vector2i] = []
	var current = party_position
	var max_steps = 50  # Increased from 20 to allow longer paths
	var steps = 0
	
	while current != target and steps < max_steps:
		var next_step = _get_next_step_towards(current, target)
		if next_step == current:
			print("Pathfinding stuck at (%d, %d) - no valid moves" % [current.x, current.y])
			break  # Can't move closer
		
		path.append(next_step)
		current = next_step
		steps += 1
	
	print("Generated path with %d steps (max: %d)" % [path.size(), max_steps])
	if path.size() > 0:
		print("First few steps: %s" % str(path.slice(0, 3)))
	
	return path

func _get_next_step_towards(from: Vector2i, to: Vector2i) -> Vector2i:
	var diff = to - from
	var step = Vector2i.ZERO
	
	# Move one step in the direction of the target
	if abs(diff.x) > abs(diff.y):
		step.x = 1 if diff.x > 0 else -1
	else:
		step.y = 1 if diff.y > 0 else -1
	
	var next_pos = from + step
	
	# Check if the next position is valid and passable
	if dungeon.is_valid_pos(next_pos.x, next_pos.y):
		var tile = dungeon.get_tile(next_pos.x, next_pos.y)
		if tile and tile.is_passable():
			return next_pos
	
	# Try alternative directions if direct path is blocked
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for direction in directions:
		var alt_pos = from + direction
		if dungeon.is_valid_pos(alt_pos.x, alt_pos.y):
			var tile = dungeon.get_tile(alt_pos.x, alt_pos.y)
			if tile and tile.is_passable():
				# Don't require unvisited - allow revisiting tiles to get to new areas
				return alt_pos
	
	print("No valid moves from (%d, %d) towards (%d, %d)" % [from.x, from.y, to.x, to.y])
	return from  # Can't move

func _process_tile_encounter(tile) -> Dictionary:
	var result = _create_step_result("Moved to (%d, %d)" % [party_position.x, party_position.y])
	
	match tile.tile_type:
		DungeonTileResource.TREASURE:
			# Automatic treasure collection - no pause needed
			var gold_found = tile.treasure_value
			result.gold_found = gold_found
			result.message = "Found treasure worth %d gold!" % gold_found
			result.event_type = "treasure"
			# Party automatically collects and continues exploring
			
		DungeonTileResource.MONSTER:
			# Auto-resolve combat for now (until combat system is implemented)
			result.monster_level = tile.monster_level
			result.monster_count = tile.monster_count
			
			# Simple combat resolution based on party strength vs monster strength
			var monster_strength = tile.monster_level * tile.monster_count * 15
			var combat_success = _resolve_auto_combat(monster_strength)
			
			if combat_success:
				var combat_gold = tile.monster_count * tile.monster_level * 3
				result.gold_found = combat_gold
				result.message = "Defeated %d monsters (Level %d) and found %d gold!" % [tile.monster_count, tile.monster_level, combat_gold]
				result.event_type = "combat_victory"
			else:
				# Failed combat - party retreats but continues exploring
				result.message = "Encountered %d strong monsters (Level %d) - party retreated!" % [tile.monster_count, tile.monster_level]
				result.event_type = "combat_retreat"
			
		DungeonTileResource.EXIT:
			result.message = "Reached the dungeon exit!"
			result.event_type = "exit"
			result.bonus_gold = dungeon.difficulty_level * 10
			# Continue exploring even after finding exit to discover all areas
			
		DungeonTileResource.ENTRANCE:
			result.message = "At dungeon entrance"
			result.event_type = "entrance"
			
		DungeonTileResource.BOSS:
			# Boss encounters - auto-resolve for now
			var boss_strength = tile.monster_level * 25
			var boss_victory = _resolve_auto_combat(boss_strength)
			
			if boss_victory:
				var boss_gold = tile.monster_level * 20
				result.gold_found = boss_gold
				result.message = "Defeated the dungeon boss! Found %d gold!" % boss_gold
				result.event_type = "boss_victory"
			else:
				result.message = "Encountered a powerful boss - party barely escaped!"
				result.event_type = "boss_retreat"
			
		_:
			result.message = "Exploring empty room"
			result.event_type = "movement"
	
	return result

func _resolve_auto_combat(enemy_strength: int) -> bool:
	# Simple combat resolution: party strength vs enemy strength with some randomness
	var party_roll = party_strength + rng.randi_range(-party_strength/4, party_strength/4)
	var enemy_roll = enemy_strength + rng.randi_range(-enemy_strength/4, enemy_strength/4)
	
	return party_roll > enemy_roll

func _create_step_result(message: String) -> Dictionary:
	return {
		"step": moves_made,
		"position": party_position,
		"message": message,
		"event_type": "movement",
		"gold_found": 0,
		"monster_level": 0,
		"monster_count": 0,
		"bonus_gold": 0,
		"tiles_explored": visited_tiles.size(),
		"navigation_score": party_navigation
	}

func _finish_exploration():
	current_state = ExplorationState.FINISHED
	
	var final_result = {
		"success": true,
		"total_moves": moves_made,
		"tiles_explored": visited_tiles.size(),
		"navigation_score": party_navigation,
		"exploration_efficiency": float(visited_tiles.size()) / float(dungeon.get_all_room_tiles().size()),
		"visited_positions": visited_tiles.duplicate()
	}
	
	exploration_finished.emit(final_result)

func get_exploration_summary() -> Dictionary:
	return {
		"state": current_state,
		"moves_made": moves_made,
		"tiles_explored": visited_tiles.size(),
		"party_position": party_position,
		"navigation_score": party_navigation,
		"targets_remaining": exploration_targets.size()
	}
