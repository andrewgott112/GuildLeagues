# scripts/managers/DraftCoordinator.gd
class_name DraftCoordinator
extends Node

const AITeamResource = preload("res://resources/AITeam.gd")
const AdventurerResource = preload("res://resources/Adventurer.gd")
const RoleResource = preload("res://resources/Role.gd")

signal draft_completed(results: Dictionary)

# Draft results tracking
var all_drafted_adventurers: Dictionary = {}  # team_id -> Array[Characters]

## Public API

func initialize_draft(ai_teams: Array) -> void:
	"""Prepare for new draft"""
	all_drafted_adventurers.clear()
	for ai_team in ai_teams:
		all_drafted_adventurers[ai_team.team_id] = []

func simulate_ai_draft(ai_teams: Array, player_picks: Array) -> Dictionary:
	"""
	Simulate AI teams making draft picks.
	player_picks: Characters the player already selected (to avoid duplication)
	Returns: { team_id: [Array of drafted characters] }
	"""
	print("[DraftCoordinator] Simulating AI draft...")
	
	# Generate prospect pool (excluding player picks)
	var prospect_pool = _generate_prospects(20, player_picks)
	
	# Each AI team picks characters
	for ai_team in ai_teams:
		var team_picks = []
		
		for pick_num in range(3):  # 3 picks per team
			if prospect_pool.is_empty():
				break
			
			var chosen_index = _ai_choose_prospect(ai_team, prospect_pool)
			var chosen_character = prospect_pool[chosen_index]
			prospect_pool.remove_at(chosen_index)
			
			team_picks.append(chosen_character)
			print("[DraftCoordinator] %s drafted %s" % [ai_team.team_name, chosen_character.name])
		
		all_drafted_adventurers[ai_team.team_id] = team_picks
	
	return all_drafted_adventurers.duplicate()

func get_draft_results() -> Dictionary:
	"""Get current draft results"""
	return all_drafted_adventurers.duplicate()

## Private helpers

func _generate_prospects(count: int, exclude_list: Array = []) -> Array:
	"""Generate random prospects, excluding specified characters"""
	var prospects = []
	
	var role_files = [
		"res://data/roles/navigator_role.tres",
		"res://data/roles/healer_role.tres",
		"res://data/roles/tank_role.tres",
		"res://data/roles/damage_role.tres"
	]
	
	var roles: Array[RoleResource] = []
	for role_path in role_files:
		var role = load(role_path) as RoleResource
		if role:
			roles.append(role)
	
	if roles.is_empty():
		push_warning("[DraftCoordinator] No roles found")
		return prospects
	
	# Generate prospects
	for i in range(count):
		var prospect = AdventurerResource.generate_random_prospect(roles)
		
		# Ensure not in exclude list
		var is_duplicate = false
		for excluded in exclude_list:
			if excluded.name == prospect.name:
				is_duplicate = true
				break
		
		if not is_duplicate:
			prospects.append(prospect)
	
	return prospects

func _ai_choose_prospect(ai_team: AITeamResource, prospects: Array) -> int:
	"""AI logic for choosing best prospect for team"""
	var best_index = 0
	var best_score = -1.0
	
	for i in range(prospects.size()):
		var prospect = prospects[i]
		var score = float(prospect.attack + prospect.defense + prospect.hp + prospect.role_stat) / 4.0
		
		# Team personality modifiers
		if ai_team.aggression > 0.7:
			score += prospect.attack * 0.3
		if ai_team.discipline > 0.7:
			score += prospect.defense * 0.3
		
		# Random factor
		score += randf_range(-10, 10)
		
		if score > best_score:
			best_score = score
			best_index = i
	
	return best_index
