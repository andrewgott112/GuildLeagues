# scripts/managers/AITeamManager.gd
class_name AITeamManager
extends Node

const AITeamResource = preload("res://resources/AITeam.gd")

var ai_teams: Array = []
var league_size: int = 8

func initialize_teams() -> void:
	"""Create AI teams for league"""
	ai_teams.clear()
	
	for i in range(league_size - 1):
		var difficulty_tier = 1 + (i / 3)
		var ai_team = AITeamResource.generate_ai_team(i, difficulty_tier)
		ai_team.roster = []  # Empty until draft
		ai_teams.append(ai_team)
		print("[AITeamManager] Created: %s" % ai_team.team_name)

func assign_draft_picks(draft_results: Dictionary, contract_manager: ContractManager, current_season: int) -> Dictionary:
	"""
	Assign drafted players to AI teams AND create contracts.
	Returns: { "success_count": int, "failed_signings": Array }
	"""
	print("[AITeamManager] Assigning draft picks and creating contracts...")
	
	var success_count = 0
	var failed_signings = []
	
	for ai_team in ai_teams:
		if not draft_results.has(ai_team.team_id):
			continue
		
		var picks = draft_results[ai_team.team_id]
		
		for character in picks:
			var seasons = 3
			var salary = character.wage
			
			# CRITICAL: Create contract for AI pick
			var result = contract_manager.sign_contract(character, ai_team, seasons, salary, current_season)
			
			if result.success:
				# Add to roster only on success
				ai_team.roster.append(character)
				success_count += 1
			else:
				# Track failures
				failed_signings.append({
					"team": ai_team.team_name,
					"character": character.name,
					"error": result.error
				})
				push_warning("[AITeamManager] %s failed to sign %s: %s" % [
					ai_team.team_name, character.name, result.error
				])
	
	return {
		"success_count": success_count,
		"failed_signings": failed_signings
	}

func update_salary_commitments(contract_manager: ContractManager) -> void:
	"""Sync AI team cached salary data"""
	for ai_team in ai_teams:
		var contracts = contract_manager.get_contracts_for_team(ai_team)
		ai_team.update_salary_commitments(contracts)

func get_all_teams_with_player(player_team) -> Array:
	"""Get all teams including player"""
	var all_teams = [player_team]
	all_teams.append_array(ai_teams)
	return all_teams

func generate_emergency_roster() -> Array:
	"""Fallback roster if draft fails"""
	var roster = []
	
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
	
	if not roles.is_empty():
		for i in range(3):
			roster.append(AdventurerResource.generate_random_prospect(roles))
	
	return roster
