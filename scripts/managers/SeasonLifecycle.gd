# scripts/managers/SeasonLifecycle.gd
class_name SeasonLifecycle
extends Node

signal phase_changed(new_phase: int)  # Game.Phase enum
signal season_changed(new_season: int)
signal season_completed(results: Dictionary)

# Phase tracking
var current_phase: int = 0  # Game.Phase.GUILD
var current_season: int = 1

# Season stats
var season_stats: Dictionary = {
	"dungeons_completed": 0,
	"total_gold_earned": 0,
	"monsters_defeated": 0,
	"playoff_performance": ""
}

# Historical tracking
var season_results: Dictionary = {}  # season_number -> results dict

# Character lifecycle tracking
var retired_characters: Array = []
var deceased_characters: Array = []

func finalize_season_results() -> void:
	"""
	Finalize the current season's results with playoff data.
	Call this AFTER playoffs complete but BEFORE advance_season().
	"""
	var current_result = season_results.get(current_season)
	if current_result:
		# Ensure playoff performance is captured
		if current_result.player_performance == "":
			current_result.player_performance = season_stats.playoff_performance
		print("[SeasonLifecycle] Season %d results finalized" % current_season)

func set_champion_info(champion_team_name: String, is_player: bool) -> void:
	"""Set the season champion before finalizing results"""
	var current_result = season_results.get(current_season)
	if current_result:
		current_result.champion = champion_team_name
		current_result.player_champion = is_player
		print("[SeasonLifecycle] Champion recorded: %s (Player: %s)" % [champion_team_name, is_player])
	else:
		push_warning("[SeasonLifecycle] Attempted to set champion but no season result exists for season %d" % current_season)

func advance_to_phase(new_phase: int) -> void:
	"""Change current phase"""
	var old_phase = current_phase
	current_phase = new_phase
	print("[SeasonLifecycle] Phase: %s -> %s" % [_phase_name(old_phase), _phase_name(new_phase)])
	emit_signal("phase_changed", new_phase)

func advance_season(rosters: Array, contract_manager: ContractManager) -> Dictionary:
	"""
	Advance to next season with full processing.
	rosters: Array of all character arrays (player + AI teams)
	contract_manager: ContractManager reference for handling contract terminations
	Returns: complete season results
	
	NOTE: Champion info should already be set via set_champion_info() 
		  and finalize_season_results() before calling this method!
	"""
	print("[SeasonLifecycle] ===== ADVANCING TO SEASON %d =====" % (current_season + 1))
	
	# Get the current season result (should already exist with champion data)
	var season_result = season_results.get(current_season)
	
	# 1. Process character aging/lifecycle (NOW with contract termination)
	var aging_results = _process_character_aging(rosters, contract_manager)
	
	# 2. Process contract expirations
	var contract_results = contract_manager.process_contract_expirations()
	
	# 3. Update season results with final data
	if season_result:
		# Merge in the lifecycle and contract data
		season_result.character_lifecycle = aging_results
		season_result.contract_expirations = contract_results
		print("[SeasonLifecycle] Updated existing season %d result" % current_season)
	else:
		# Fallback: create new result if somehow it doesn't exist
		push_warning("[SeasonLifecycle] No pre-existing season result! Creating one now.")
		season_result = {
			"season": current_season,
			"champion": "Unknown",
			"player_champion": false,
			"player_performance": season_stats.get("playoff_performance", "Unknown"),
			"stats": season_stats.duplicate(),
			"character_lifecycle": aging_results,
			"contract_expirations": contract_results
		}
		season_results[current_season] = season_result
	
	# Validate champion was set
	if season_result.champion == "":
		push_warning("[SeasonLifecycle] Champion was never set for season %d!" % current_season)
	
	# 4. Increment season
	current_season += 1
	
	# 5. Reset season stats
	season_stats = {
		"dungeons_completed": 0,
		"total_gold_earned": 0,
		"monsters_defeated": 0,
		"playoff_performance": ""
	}
	
	emit_signal("season_changed", current_season)
	emit_signal("season_completed", season_result)
	
	return season_result

func record_dungeon_completion(gold_earned: int, monsters_defeated: int) -> void:
	"""Track dungeon stats"""
	season_stats.dungeons_completed += 1
	season_stats.total_gold_earned += gold_earned
	season_stats.monsters_defeated += monsters_defeated

func set_playoff_performance(performance: String) -> void:
	"""Set playoff result text"""
	season_stats.playoff_performance = performance
	
	# Also update the stored season result if it exists
	var current_result = season_results.get(current_season)
	if current_result:
		current_result.player_performance = performance

func get_season_summary(season_num: int = -1) -> Dictionary:
	"""Get results for specific season (or current if -1)"""
	var target_season = season_num if season_num >= 0 else current_season
	
	if season_results.has(target_season):
		return season_results[target_season]
	
	return {
		"season": target_season,
		"in_progress": true,
		"stats": season_stats.duplicate()
	}

func get_all_time_stats() -> Dictionary:
	"""Aggregate stats across all seasons"""
	var total_stats = {
		"seasons_played": season_results.size(),
		"championships": 0,
		"playoff_appearances": 0,
		"total_dungeons": 0,
		"total_gold": 0,
		"total_monsters": 0
	}
	
	for season_data in season_results.values():
		if season_data.get("player_champion", false):
			total_stats.championships += 1
		if season_data.get("player_performance", "") != "Did not participate":
			total_stats.playoff_appearances += 1
		
		var stats = season_data.get("stats", {})
		total_stats.total_dungeons += stats.get("dungeons_completed", 0)
		total_stats.total_gold += stats.get("total_gold_earned", 0)
		total_stats.total_monsters += stats.get("monsters_defeated", 0)
	
	# Add current season
	total_stats.total_dungeons += season_stats.get("dungeons_completed", 0)
	total_stats.total_gold += season_stats.get("total_gold_earned", 0)
	total_stats.total_monsters += season_stats.get("monsters_defeated", 0)
	
	return total_stats

func get_hall_of_fame() -> Array:
	"""Get retired characters sorted by wins"""
	var hof = retired_characters.duplicate()
	hof.sort_custom(func(a, b): return a.battles_won > b.battles_won)
	return hof

func get_memorial() -> Array:
	"""Get deceased characters"""
	return deceased_characters.duplicate()

## Private - Character Lifecycle

func _process_character_aging(rosters: Array, contract_manager: ContractManager) -> Dictionary:
	"""Age all characters and process retirements/deaths"""
	var results = {
		"aged": [],
		"retired": [],
		"deceased": [],
		"went_mad": [],
		"injuries_healed": []
	}
	
	# Track characters to remove per roster
	var removal_map = {}  # roster_index -> [characters_to_remove]
	
	for roster_idx in range(rosters.size()):
		var roster = rosters[roster_idx]
		removal_map[roster_idx] = []
		
		for character in roster:
			var char_result = _process_single_character(character)
			
			results.aged.append(character.name)
			
			# Handle retirement
			if char_result.retired:
				results.retired.append(character.name)
				if character not in retired_characters:
					retired_characters.append(character)
				removal_map[roster_idx].append(character)
			
			# Handle death (overrides retirement)
			if char_result.died:
				results.deceased.append(character.name)
				if character not in deceased_characters:
					deceased_characters.append(character)
				# Remove from retired if they were just added
				if character in retired_characters:
					retired_characters.erase(character)
				# Ensure they're marked for removal
				if character not in removal_map[roster_idx]:
					removal_map[roster_idx].append(character)
			
			# Handle madness (also counts as removal)
			if char_result.went_mad:
				results.went_mad.append(character.name)
				if character not in deceased_characters:
					deceased_characters.append(character)
				# Ensure they're marked for removal
				if character not in removal_map[roster_idx]:
					removal_map[roster_idx].append(character)
			
			if char_result.injuries_healed > 0:
				results.injuries_healed.append("%s (%d)" % [character.name, char_result.injuries_healed])
	
	# Now remove all marked characters and terminate contracts
	for roster_idx in removal_map.keys():
		var roster = rosters[roster_idx]
		var to_remove = removal_map[roster_idx]
		
		for character in to_remove:
			# Remove from roster
			roster.erase(character)
			
			# Terminate contract
			var contract = contract_manager.get_contract_for_character(character)
			if contract:
				contract_manager.terminate_contract(contract)
				print("[SeasonLifecycle] Terminated contract for %s (retired/deceased)" % character.name)
	
	return results

func _process_single_character(character) -> Dictionary:
	"""Process one character's end-of-season updates"""
	var result = {
		"injuries_healed": 0,
		"retired": false,
		"died": false,
		"went_mad": false
	}
	
	# Age character
	character.apply_aging()
	
	# Process injury recovery
	if character.has_method("process_injury_recovery"):
		var injuries_before = character.injuries.size()
		character.process_injury_recovery()
		result.injuries_healed = injuries_before - character.injuries.size()
	
	# Check retirement (age-based)
	if character.age > character.peak_age + 5:
		var retirement_chance = (character.age - character.peak_age - 5) * 0.15
		if randf() < retirement_chance:
			character.is_retired = true
			result.retired = true
	
	# Check madness
	if character.madness_level >= 100:
		result.went_mad = true
	
	# Check natural death (very old characters)
	if character.age > character.peak_age + 8:
		if randf() < 0.02:  # 2% chance
			result.died = true
	
	return result

## Private helpers

func _phase_name(phase_val: int) -> String:
	match phase_val:
		0: return "Guild"      # Game.Phase.GUILD
		1: return "Dungeons"   # Game.Phase.DUNGEONS
		2: return "Playoffs"   # Game.Phase.PLAYOFFS
		3: return "Draft"      # Game.Phase.DRAFT
		_: return "Unknown"
