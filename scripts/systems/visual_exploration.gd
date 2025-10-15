# scripts/systems/visual_exploration.gd
extends Node
class_name VisualExploration

signal exploration_step_complete(result: Dictionary)
signal exploration_finished(final_result: Dictionary)
signal monster_encounter(encounter_data: Dictionary)

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
var retreated_tiles: Array[Vector2i] = []
var exploration_targets: Array[Vector2i] = []
var current_path: Array[Vector2i] = []
var exploration_progress: Dictionary = {}
var pending_battle_tile = null

# Gold and exit management
var gold_capacity: int = 100  # v0.1 flat cap, expand later
var current_gold_carried: int = 0
var exit_position: Vector2i = Vector2i(-1, -1)
var exit_found: bool = false
var decided_to_exit: bool = false

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
		var empty_tiles = dungeon.find_tiles_of_type(DungeonTileResource.EMPTY)
		if empty_tiles.is_empty():
			return false
		party_position = empty_tiles[0].position
	else:
		party_position = entrance_tiles[0].position
	
	# Initialize exploration
	visited_tiles.clear()
	retreated_tiles.clear()
	exploration_targets.clear()
	current_path.clear()
	moves_made = 0
	
	# Initialize gold and exit tracking
	current_gold_carried = 0
	exit_position = Vector2i(-1, -1)
	exit_found = false
	decided_to_exit = false
	
	# Clear oscillation tracking
	if has_meta("recent_positions"):
		set_meta("recent_positions", [])
	
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
	
	# SAFETY CHECK: Hard limit to prevent infinite exploration
	if moves_made > 100:  # Absolute maximum
		_finish_exploration_early("Party exhausted - forced to exit")
		return exploration_progress
	
	# Check if party decides to exit
	if _should_party_exit():
		if exit_found and exit_position != Vector2i(-1, -1):
			_head_to_exit()
		else:
			# If no exit found but party wants to leave, end exploration
			_finish_exploration_early("Party decided to leave (no exit found)")
			return exploration_progress
	
	# Check if we have a path to follow
	if current_path.is_empty():
		print("No current path, finding next destination...")
		_find_next_destination()
	
	# If still no path, exploration might be done
	if current_path.is_empty():
		# Instead of continuing forever, be more decisive about ending
		if exploration_targets.is_empty():
			print("No path and no targets - finishing exploration")
			if exit_found:
				_head_to_exit()
			else:
				_finish_exploration_early("No more accessible areas to explore")
			return exploration_progress
		else:
			# Try one more time to find any valid move
			print("No path but have targets - trying emergency pathfinding...")
			_emergency_pathfinding()
			if current_path.is_empty():
				print("Emergency pathfinding failed - ending exploration")
				_finish_exploration_early("Unable to reach remaining areas")
				return exploration_progress
	
	# Oscillation detection - track last few positions
	if not has_meta("recent_positions"):
		set_meta("recent_positions", [])
	
	var recent_positions = get_meta("recent_positions")
	
	# Move to next position in path
	var next_pos = current_path.pop_front()
	
	# Check for oscillation before moving
	if party_position in recent_positions:
		var recent_count = recent_positions.count(party_position)
		if recent_count >= 2:
			print("Oscillation detected! Party has been at (%d, %d) %d times recently" % [party_position.x, party_position.y, recent_count])
			# Clear path and try emergency exit
			current_path.clear()
			set_meta("recent_positions", [])
			if exit_found:
				_head_to_exit()
				return _create_step_result("Party breaks oscillation and heads to exit")
			else:
				_finish_exploration_early("Party stuck in loop - forced exit")
				return exploration_progress
	
	party_position = next_pos
	moves_made += 1
	
	# Track recent positions (keep last 6 instead of 8)
	recent_positions.append(party_position)
	if recent_positions.size() > 6:
		recent_positions.pop_front()
	set_meta("recent_positions", recent_positions)

	if party_position in exploration_targets:
		exploration_targets.erase(party_position)

	if party_position not in visited_tiles:
		visited_tiles.append(party_position)

	# Check what's at this position
	var tile = dungeon.get_tile(party_position.x, party_position.y)
	var step_result = _process_tile_encounter(tile)
	
	if step_result.event_type == "combat_encounter":
		exploration_progress = step_result
		exploration_step_complete.emit(step_result)
		return step_result  # Exit early, don't process anything else
	
	# Handle retreats
	if step_result.event_type in ["combat_retreat", "boss_retreat"]:
		if party_position not in retreated_tiles:
			retreated_tiles.append(party_position)
			print("Added retreat position: (%d, %d)" % [party_position.x, party_position.y])
		current_path.clear()
		# Clear recent positions after retreat to avoid confusion
		set_meta("recent_positions", [])
	
	# Handle gold collection
	if step_result.gold_found > 0:
		var gold_to_collect = min(step_result.gold_found, gold_capacity - current_gold_carried)
		current_gold_carried += gold_to_collect
		step_result.gold_collected = gold_to_collect
		step_result.gold_left_behind = step_result.gold_found - gold_to_collect
		
		if gold_to_collect < step_result.gold_found:
			step_result.message += " (Carrying capacity reached! Left %d gold behind)" % step_result.gold_left_behind
	
	# Track exit discovery
	if step_result.event_type == "exit" and not exit_found:
		exit_found = true
		exit_position = party_position
		step_result.message += " (Exit located for future use)"
	
	# Discover new targets
	_discover_nearby_targets()
	
	exploration_progress = step_result
	exploration_step_complete.emit(step_result)
	
	return step_result

# Exit decision logic
func _should_party_exit() -> bool:
	if decided_to_exit:
		return true
	
	var exit_score = 0.0
	var reasons = []
	
	# HARD LIMITS - Always exit after these thresholds
	if moves_made > 80:  # Hard cap - was too high before
		decided_to_exit = true
		return true
	
	if current_gold_carried >= gold_capacity:  # Always exit when full
		decided_to_exit = true
		return true
	
	# Factor 1: Gold capacity (more aggressive)
	var gold_percentage = float(current_gold_carried) / float(gold_capacity)
	if gold_percentage >= 0.8:
		exit_score += 60.0  # Increased from 50.0
		reasons.append("heavy load")
	elif gold_percentage >= 0.6:
		exit_score += 30.0  # Increased from 20.0
		reasons.append("good haul")
	elif gold_percentage >= 0.4:
		exit_score += 15.0  # New threshold
		reasons.append("some gold")
	
	# Factor 2: Moves made (fatigue kicks in sooner)
	if moves_made > 50:  # Reduced from 50
		exit_score += 40.0  # Increased penalty
		reasons.append("party exhaustion")
	elif moves_made > 30:  # Reduced from 30  
		exit_score += 20.0  # Increased penalty
		reasons.append("getting tired")
	elif moves_made > 20:
		exit_score += 10.0  # New earlier threshold
	
	# Factor 3: Retreat count (danger assessment) - more aggressive
	var retreat_count = retreated_tiles.size()
	if retreat_count >= 2:  # Reduced from 3
		exit_score += 50.0  # Increased from 40.0
		reasons.append("too dangerous")
	elif retreat_count >= 1:
		exit_score += 25.0  # New threshold
		reasons.append("dangerous encounters")
	
	# Factor 4: Target scarcity (more aggressive)
	if exploration_targets.size() <= 3 and visited_tiles.size() > 8:  # Reduced thresholds
		exit_score += 35.0  # Increased from 25.0
		reasons.append("few targets remaining")
	elif exploration_targets.size() <= 1:
		exit_score += 50.0  # High score for almost no targets
		reasons.append("nearly fully explored")
	
	# Factor 5: Navigation skill affects confidence (rebalanced)
	if party_navigation < 20:  # Poor navigators get nervous faster
		exit_score += 20.0
		if moves_made > 15:
			exit_score += 20.0
			reasons.append("poor navigation skills")
	elif party_navigation > 60:  # Good navigators are more confident
		exit_score -= 10.0  # Reduced penalty
	
	# Factor 6: Exit availability bonus
	if exit_found:
		exit_score += 10.0  # Bonus for knowing the way out
	else:
		exit_score -= 10.0  # Penalty for not knowing exit (reduced from -20)
	
	# Factor 7: Efficiency check - if we're not finding much, leave
	if moves_made > 15:
		var tiles_per_move = float(visited_tiles.size()) / float(moves_made)
		if tiles_per_move < 0.7:  # Not exploring efficiently
			exit_score += 25.0
			reasons.append("inefficient exploration")
	
	# Decision threshold (lowered to be more aggressive)
	var exit_threshold = 40.0  # Reduced from 50.0
	
	if exit_score >= exit_threshold:
		decided_to_exit = true
		var reason_text = " (" + ", ".join(reasons) + ")" if reasons.size() > 0 else ""
		print("Party decides to exit! Score: %.1f %s" % [exit_score, reason_text])
		return true
	
	return false

# Head to exit when party decides to leave
func _head_to_exit():
	if party_position == exit_position:
		_finish_exploration_early("Party successfully exited the dungeon")
		return
	
	# Clear current path and set exit as only target
	current_path.clear()
	exploration_targets.clear()
	exploration_targets.append(exit_position)
	
	print("Party heading to exit at (%d, %d)" % [exit_position.x, exit_position.y])
	
	# Try to find path to exit immediately
	current_path = _find_path_to_target(exit_position)
	if current_path.is_empty():
		print("WARNING: Cannot find path to exit! Ending exploration anyway.")
		_finish_exploration_early("Party attempted to exit but couldn't find path")

func _calculate_navigation_skill(party_data: Array) -> int:
	var total_navigation = 0
	var navigator_bonus = 0
	
	print("=== Navigation Calculation Debug ===")
	
	for adventurer in party_data:
		var is_navigator = false
		
		# Check by role ID (most reliable)
		if adventurer.role and adventurer.role.id == &"navigator":
			is_navigator = true
		# Fallback: check by role_stat_name (with proper StringName handling)
		elif adventurer.role and adventurer.role.role_stat_name:
			var role_stat_name_str = str(adventurer.role.role_stat_name).to_lower()
			if role_stat_name_str in ["navigation", "navigate"]:
				is_navigator = true
		
		if is_navigator:
			total_navigation += adventurer.role_stat * 2
			navigator_bonus += 5
			print("%s (Navigator): %d * 2 = %d + 5 bonus" % [adventurer.name, adventurer.role_stat, adventurer.role_stat * 2])
		else:
			var contribution = max(1, adventurer.role_stat / 2)
			total_navigation += contribution
			print("%s (%s): %d / 2 = %d" % [adventurer.name, adventurer.role.display_name if adventurer.role else "No Role", adventurer.role_stat, contribution])
	
	var party_size_bonus = party_data.size() * 2
	var final_score = total_navigation + navigator_bonus + party_size_bonus
	
	print("Navigator bonus: %d" % navigator_bonus)
	print("Party size bonus (%d members): %d" % [party_data.size(), party_size_bonus])
	print("Final navigation score: %d" % final_score)
	print("=====================================")
	
	return final_score

func _calculate_party_strength(party_data: Array) -> int:
	var total_strength = 0
	for adventurer in party_data:
		total_strength += adventurer.attack + adventurer.defense + (adventurer.hp / 5)
	return total_strength

func _discover_nearby_targets():
	var vision_range = 2 + (party_navigation / 20)
	
	for y in range(party_position.y - vision_range, party_position.y + vision_range + 1):
		for x in range(party_position.x - vision_range, party_position.x + vision_range + 1):
			if not dungeon.is_valid_pos(x, y):
				continue
			
			var pos = Vector2i(x, y)
			if pos == party_position or pos in visited_tiles or pos in retreated_tiles:
				continue
			
			var tile = dungeon.get_tile(x, y)
			if not tile or not tile.is_passable():
				continue
			
			# Prioritize exit if party wants to leave
			if decided_to_exit and tile.tile_type == DungeonTileResource.EXIT:
				if pos not in exploration_targets:
					exploration_targets.append(pos)
				continue
			
			# Skip other targets if heading to exit
			if decided_to_exit:
				continue
			
			if tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.MONSTER, DungeonTileResource.EXIT]:
				if tile.tile_type in [DungeonTileResource.MONSTER, DungeonTileResource.BOSS] and pos in retreated_tiles:
					continue
				if pos not in exploration_targets:
					exploration_targets.append(pos)
			elif tile.tile_type == DungeonTileResource.EMPTY:
				if rng.randf() < 0.7 and pos not in exploration_targets:
					exploration_targets.append(pos)
	
	if exploration_targets.size() < 3 and not decided_to_exit:
		_expand_target_search()

func _find_next_destination():
	current_path.clear()
	print("Finding next destination from (%d, %d)" % [party_position.x, party_position.y])
	
	# Remove retreated positions from targets
	for retreated_pos in retreated_tiles:
		if retreated_pos in exploration_targets:
			exploration_targets.erase(retreated_pos)
	
	# If we have no targets, try to find some
	if exploration_targets.is_empty() and not decided_to_exit:
		_find_unexplored_areas()
	
	# If still no targets, try even harder
	if exploration_targets.is_empty() and not decided_to_exit:
		_find_any_unvisited_areas()
	
	# If STILL no targets, we're probably done
	if exploration_targets.is_empty():
		print("No targets found - exploration should end")
		return
	
	print("Have %d targets available" % exploration_targets.size())
	
	var best_target = _choose_best_target()
	if best_target == Vector2i(-1, -1):
		print("No valid target chosen")
		return
	
	print("Chosen target: (%d, %d)" % [best_target.x, best_target.y])
	
	current_path = _find_path_to_target(best_target)
	if current_path.is_empty():
		print("Failed to find path to target (%d, %d)" % [best_target.x, best_target.y])
		exploration_targets.erase(best_target)
		
		# If we can't reach our best target, try a few more before giving up
		var attempts = 0
		while current_path.is_empty() and exploration_targets.size() > 0 and attempts < 3:
			best_target = _choose_best_target()
			if best_target != Vector2i(-1, -1):
				current_path = _find_path_to_target(best_target)
				if current_path.is_empty():
					exploration_targets.erase(best_target)
			attempts += 1
		
		if current_path.is_empty():
			print("Cannot reach any targets after %d attempts" % attempts)
	else:
		print("Found path with %d steps" % current_path.size())
		exploration_targets.erase(best_target)

func _find_unexplored_areas():
	var empty_tiles = dungeon.find_tiles_of_type(DungeonTileResource.EMPTY)
	
	for tile in empty_tiles:
		if tile.position not in visited_tiles and tile.position not in retreated_tiles:
			exploration_targets.append(tile.position)
	
	var special_types = [DungeonTileResource.TREASURE, DungeonTileResource.EXIT]
	for tile_type in special_types:
		var special_tiles = dungeon.find_tiles_of_type(tile_type)
		for tile in special_tiles:
			if tile.position not in visited_tiles and tile.position not in exploration_targets and tile.position not in retreated_tiles:
				exploration_targets.append(tile.position)

func _find_any_unvisited_areas():
	for y in range(dungeon.height):
		for x in range(dungeon.width):
			var pos = Vector2i(x, y)
			if pos in visited_tiles or pos in retreated_tiles:
				continue
				
			var tile = dungeon.get_tile(x, y)
			if tile and tile.is_passable():
				if tile.tile_type in [DungeonTileResource.MONSTER, DungeonTileResource.BOSS] and pos in retreated_tiles:
					continue
				exploration_targets.append(pos)

func _expand_target_search():
	var expanded_range = 8
	
	for y in range(party_position.y - expanded_range, party_position.y + expanded_range + 1):
		for x in range(party_position.x - expanded_range, party_position.x + expanded_range + 1):
			if not dungeon.is_valid_pos(x, y):
				continue
			
			var pos = Vector2i(x, y)
			if pos == party_position or pos in visited_tiles or pos in exploration_targets or pos in retreated_tiles:
				continue
			
			var tile = dungeon.get_tile(x, y)
			if tile and tile.is_passable():
				if tile.tile_type in [DungeonTileResource.MONSTER, DungeonTileResource.BOSS] and pos in retreated_tiles:
					continue
				exploration_targets.append(pos)
				if exploration_targets.size() >= 10:
					break
		if exploration_targets.size() >= 10:
			break

func _choose_best_target() -> Vector2i:
	if exploration_targets.is_empty():
		return Vector2i(-1, -1)

	var best_target := Vector2i(-1, -1)
	var best_score := -1e20

	for target in exploration_targets:
		if target == party_position or target in retreated_tiles:
			continue
		
		var tile = dungeon.get_tile(target.x, target.y)
		if not tile:
			continue
		
		var score = 0.0
		var distance = Vector2(party_position).distance_to(Vector2(target))
		
		# If heading to exit, prioritize exit heavily
		if decided_to_exit and tile.tile_type == DungeonTileResource.EXIT:
			score = 1000.0 - distance * 1.0
		elif decided_to_exit:
			continue  # Skip non-exit targets when heading to exit
		else:
			match tile.tile_type:
				DungeonTileResource.TREASURE:
					# Lower priority if near gold capacity
					var gold_factor = 1.0 - (float(current_gold_carried) / float(gold_capacity)) * 0.5
					score = 100.0 * gold_factor - distance * 2.0
				DungeonTileResource.EXIT:
					score = 80.0 - distance * 1.5
				DungeonTileResource.MONSTER:
					score = 40.0 - distance * 1.0
				DungeonTileResource.EMPTY:
					score = 30.0 - distance * 3.0
		
		if party_navigation > 30:
			if tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.EXIT]:
				score *= 1.5
		
		if score > best_score:
			best_score = score
			best_target = target
	
	return best_target

func _find_path_to_target(target: Vector2i) -> Array[Vector2i]:
	print("Finding path from (%d, %d) to (%d, %d)" % [party_position.x, party_position.y, target.x, target.y])
	
	# Enhanced pathfinding with oscillation prevention
	var path: Array[Vector2i] = []
	var current = party_position
	var max_steps = 50
	var steps = 0
	
	# Track recent positions to prevent oscillation
	var recent_positions: Array[Vector2i] = []
	var max_recent_memory = 6  # Remember last 6 positions
	
	# Failed move tracking
	var failed_moves: Dictionary = {}  # pos -> count of failures
	
	while current != target and steps < max_steps:
		var next_step = _get_next_step_towards_smart(current, target, recent_positions, failed_moves)
		
		if next_step == current:
			print("Pathfinding stuck at (%d, %d) - no valid moves available" % [current.x, current.y])
			break
		
		# Check if this would create immediate oscillation
		if recent_positions.size() >= 2 and next_step == recent_positions[-2]:
			print("Detected immediate oscillation attempt from (%d, %d) to (%d, %d)" % [current.x, current.y, next_step.x, next_step.y])
			# Try to find a different move
			next_step = _find_non_oscillating_move(current, target, recent_positions, failed_moves)
			if next_step == current:
				print("No non-oscillating move found, breaking path")
				break
		
		# Add to path and update tracking
		path.append(next_step)
		recent_positions.append(current)
		
		# Limit memory size
		if recent_positions.size() > max_recent_memory:
			recent_positions.pop_front()
		
		current = next_step
		steps += 1
		
		# Detect if we've been here too recently
		var recent_visits = recent_positions.count(current)
		if recent_visits >= 3:
			print("Visited (%d, %d) too many times recently (%d), aborting path" % [current.x, current.y, recent_visits])
			break
	
	print("Generated path with %d steps (max: %d)" % [path.size(), max_steps])
	if path.size() > 0 and path.size() <= 10:
		print("Path steps: %s" % str(path))
	elif path.size() > 10:
		print("Long path, first 5 steps: %s" % str(path.slice(0, 5)))
	
	return path

# Smarter pathfinding that considers recent positions and failures
func _get_next_step_towards_smart(from: Vector2i, to: Vector2i, recent_positions: Array[Vector2i], failed_moves: Dictionary) -> Vector2i:
	var diff = to - from
	
	# Calculate all possible directions with scores
	var move_options = []
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	
	for direction in directions:
		var test_pos = from + direction
		
		if not _is_valid_move(test_pos):
			continue
		
		var score = _calculate_move_score(test_pos, to, recent_positions, failed_moves)
		move_options.append({"pos": test_pos, "score": score, "direction": direction})
	
	if move_options.is_empty():
		return from  # No valid moves
	
	# Sort by score (higher is better)
	move_options.sort_custom(func(a, b): return a.score > b.score)
	
	# Pick the best move that doesn't create immediate oscillation
	for option in move_options:
		var test_pos = option.pos
		
		# Avoid immediate back-and-forth
		if recent_positions.size() >= 1 and test_pos == recent_positions[-1]:
			continue
		
		# Avoid three-position cycles  
		if recent_positions.size() >= 2 and test_pos == recent_positions[-2]:
			continue
		
		print("Chose move to (%d, %d) with score %.1f" % [test_pos.x, test_pos.y, option.score])
		return test_pos
	
	# If all moves would oscillate, pick the least bad one
	if move_options.size() > 0:
		var fallback = move_options[0].pos
		print("All moves would oscillate, using fallback to (%d, %d)" % [fallback.x, fallback.y])
		return fallback
	
	return from

# Calculate a score for potential moves
func _calculate_move_score(pos: Vector2i, target: Vector2i, recent_positions: Array[Vector2i], failed_moves: Dictionary) -> float:
	var score = 0.0
	
	# Distance to target (primary factor)
	var distance = Vector2(pos).distance_to(Vector2(target))
	score = 100.0 - distance * 10.0  # Closer is much better
	
	# Heavily penalize recently visited positions
	var recent_visit_count = recent_positions.count(pos)
	score -= recent_visit_count * 50.0
	
	# Penalize failed moves
	var pos_key = str(pos.x) + "," + str(pos.y)
	if failed_moves.has(pos_key):
		score -= failed_moves[pos_key] * 20.0
	
	# Small random factor to break ties
	score += rng.randf_range(-1.0, 1.0)
	
	return score

# Find a move that doesn't oscillate
func _find_non_oscillating_move(from: Vector2i, target: Vector2i, recent_positions: Array[Vector2i], failed_moves: Dictionary) -> Vector2i:
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var valid_moves = []
	
	for direction in directions:
		var test_pos = from + direction
		
		if not _is_valid_move(test_pos):
			continue
		
		# Skip if this would be immediate oscillation
		if recent_positions.size() >= 1 and test_pos == recent_positions[-1]:
			continue
		if recent_positions.size() >= 2 and test_pos == recent_positions[-2]:
			continue
		
		var distance = Vector2(test_pos).distance_to(Vector2(target))
		valid_moves.append({"pos": test_pos, "distance": distance})
	
	if valid_moves.is_empty():
		return from
	
	# Sort by distance to target
	valid_moves.sort_custom(func(a, b): return a.distance < b.distance)
	return valid_moves[0].pos

func _is_valid_move(pos: Vector2i) -> bool:
	if not dungeon.is_valid_pos(pos.x, pos.y):
		return false
	
	var tile = dungeon.get_tile(pos.x, pos.y)
	if not tile or not tile.is_passable():
		return false
	
	if pos in retreated_tiles:
		return false
	
	return true

func _process_tile_encounter(tile) -> Dictionary:
	var result = _create_step_result("Moved to (%d, %d)" % [party_position.x, party_position.y])
	
	match tile.tile_type:
		DungeonTileResource.TREASURE:
			if not tile.cleared:
				var gold_found = tile.treasure_value
				result.gold_found = gold_found
				result.message = "Found treasure worth %d gold!" % gold_found
				result.event_type = "treasure"
				tile.cleared = true
			else:
				result.message = "An empty treasure chest (already looted)"
				result.event_type = "movement"
			
		DungeonTileResource.MONSTER:
			if not tile.cleared:
				result.monster_level = tile.monster_level
				result.monster_count = tile.monster_count
				
				var monster_strength = tile.monster_level * tile.monster_count * 15
				var combat_result = _resolve_combat_encounter(monster_strength, tile)
				
				if combat_result == "combat_encounter":
					result.message = "Encountered %d monsters (Level %d) - entering combat!" % [tile.monster_count, tile.monster_level]
					result.event_type = "combat_encounter"
					return result  # Don't continue processing, wait for battle result
				
				# If we get here, it was auto-resolved (shouldn't happen with new system)
			else:
				result.message = "Empty monster lair (already cleared)"
				result.event_type = "movement"
			
		DungeonTileResource.EXIT:
			result.message = "Reached the dungeon exit!"
			result.event_type = "exit"
			if not tile.cleared:
				result.bonus_gold = dungeon.difficulty_level * 10
				tile.cleared = true
			
		DungeonTileResource.ENTRANCE:
			result.message = "At dungeon entrance"
			result.event_type = "entrance"
			
		DungeonTileResource.BOSS:
			if not tile.cleared:
				result.monster_level = tile.monster_level
				result.monster_count = 1  # Bosses are always single encounters
				
				var boss_strength = tile.monster_level * 25
				var combat_result = _resolve_combat_encounter(boss_strength, tile)
				
				if combat_result == "combat_encounter":
					result.message = "Encountered a powerful boss (Level %d) - entering combat!" % tile.monster_level
					result.event_type = "combat_encounter"
					return result  # Don't continue processing, wait for battle result
				
				# If we get here, it was auto-resolved (shouldn't happen with new system)
			else:
				result.message = "Boss chamber (already defeated)"
				result.event_type = "movement"
			
		_:
			result.message = "Exploring empty room"
			result.event_type = "movement"
	
	return result

func _resolve_combat_encounter(monster_strength: int, tile) -> String:
	"""Instead of auto-resolving, emit signal for battle system"""
	# This function now properly defers to the battle system,
	# but if you had auto-resolution logic, here's a balanced version:
	
	pending_battle_tile = tile
	
	var encounter_data = {
		"monster_level": tile.monster_level,
		"monster_count": tile.monster_count,
		"monster_strength": monster_strength,
		"tile_position": tile.position,
		"is_boss": tile.tile_type == DungeonTileResource.BOSS
	}
	
	# Pause exploration and emit signal
	current_state = ExplorationState.PAUSED_FOR_ENCOUNTER
	monster_encounter.emit(encounter_data)
	
	return "combat_encounter"

# Add this method to handle battle results
func resolve_monster_encounter(battle_result: Dictionary):
	"""Called by DungeonScreen when battle is finished"""
	if pending_battle_tile == null:
		print("Warning: No pending battle tile!")
		return
	
	var tile = pending_battle_tile
	var result_data = _create_step_result("Combat resolved")
	
	if battle_result.get("victory", false):
		# Victory - clear the tile and award gold
		var combat_gold = tile.monster_count * tile.monster_level * 3
		result_data.gold_found = combat_gold
		result_data.message = "Defeated %d monsters (Level %d) and found %d gold!" % [tile.monster_count, tile.monster_level, combat_gold]
		result_data.event_type = "combat_victory"
		tile.cleared = true
		
		# Update combat stats for party members
		for adventurer in party:
			adventurer.add_battle_result(true)
			adventurer.add_monster_kill()
	else:
		# Defeat or retreat - mark as retreated
		if party_position not in retreated_tiles:
			retreated_tiles.append(party_position)
		result_data.message = "Party was defeated or retreated from combat!"
		result_data.event_type = "combat_retreat"
	
	# Resume exploration
	current_state = ExplorationState.EXPLORING
	pending_battle_tile = null
	
	# Emit the step result
	exploration_step_complete.emit(result_data)

func _create_step_result(message: String) -> Dictionary:
	return {
		"step": moves_made,
		"position": party_position,
		"message": message,
		"event_type": "movement",
		"gold_found": 0,
		"gold_collected": 0,
		"gold_left_behind": 0,
		"monster_level": 0,
		"monster_count": 0,
		"bonus_gold": 0,
		"tiles_explored": visited_tiles.size(),
		"navigation_score": party_navigation,
		"gold_carried": current_gold_carried,
		"gold_capacity": gold_capacity
	}

# Early exit function
func _finish_exploration_early(reason: String):
	current_state = ExplorationState.FINISHED
	
	var final_result = {
		"success": true,
		"total_moves": moves_made,
		"tiles_explored": visited_tiles.size(),
		"navigation_score": party_navigation,
		"exploration_efficiency": float(visited_tiles.size()) / float(dungeon.get_all_room_tiles().size()),
		"visited_positions": visited_tiles.duplicate(),
		"retreated_positions": retreated_tiles.duplicate(),
		"gold_collected": current_gold_carried,
		"exit_reason": reason,
		"early_exit": true
	}
	
	print("Exploration finished early: %s" % reason)
	exploration_finished.emit(final_result)

func _finish_exploration():
	current_state = ExplorationState.FINISHED
	
	var final_result = {
		"success": true,
		"total_moves": moves_made,
		"tiles_explored": visited_tiles.size(),
		"navigation_score": party_navigation,
		"exploration_efficiency": float(visited_tiles.size()) / float(dungeon.get_all_room_tiles().size()),
		"visited_positions": visited_tiles.duplicate(),
		"retreated_positions": retreated_tiles.duplicate(),
		"gold_collected": current_gold_carried,
		"exit_reason": "Full exploration completed",
		"early_exit": false
	}
	
	exploration_finished.emit(final_result)

func get_exploration_summary() -> Dictionary:
	return {
		"state": current_state,
		"moves_made": moves_made,
		"tiles_explored": visited_tiles.size(),
		"party_position": party_position,
		"navigation_score": party_navigation,
		"targets_remaining": exploration_targets.size(),
		"retreated_from": retreated_tiles.size(),
		"gold_carried": current_gold_carried,
		"gold_capacity": gold_capacity,
		"exit_found": exit_found,
		"decided_to_exit": decided_to_exit
	}

func _emergency_pathfinding():
	"""Try to find any valid move when normal pathfinding fails"""
	print("Attempting emergency pathfinding...")
	
	# Try to move to any adjacent passable tile
	var directions = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var valid_moves = []
	
	for direction in directions:
		var test_pos = party_position + direction
		if _is_valid_move(test_pos):
			valid_moves.append(test_pos)
	
	if valid_moves.is_empty():
		print("Emergency pathfinding: No valid moves available")
		return
	
	# Pick a random valid move
	var emergency_move = valid_moves[rng.randi() % valid_moves.size()]
	current_path = [emergency_move]
	print("Emergency pathfinding: Moving to (%d, %d)" % [emergency_move.x, emergency_move.y])
