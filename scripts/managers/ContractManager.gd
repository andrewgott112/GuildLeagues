# scripts/managers/ContractManager.gd
class_name ContractManager
extends Node

signal contract_signed(contract: Contract)
signal contract_expired(contract: Contract)
signal salary_cap_exceeded(team_id: String, overage: int)

class Contract:
	var character
	var team  # null for player, AITeamResource for AI
	var seasons_remaining: int
	var salary_per_season: int
	var signed_date: int
	var is_player_contract: bool
	
	func _init(char, team_ref, seasons: int, salary: int, season_signed: int):
		character = char
		team = team_ref
		seasons_remaining = seasons
		salary_per_season = salary
		signed_date = season_signed
		is_player_contract = (team_ref == null)
	
	func get_total_value() -> int:
		return seasons_remaining * salary_per_season
	
	func advance_season() -> bool:
		seasons_remaining -= 1
		return seasons_remaining <= 0
	
	func get_info_text() -> String:
		var team_name = "Your Guild" if is_player_contract else team.team_name
		return "%s: %d seasons @ %dg/season (Total: %dg)" % [
			character.name,
			seasons_remaining,
			salary_per_season,
			get_total_value()
		]

var active_contracts: Array[Contract] = []
var free_agent_pool: Array = []
var salary_cap: int = 100

func sign_contract(character, team_ref, seasons: int, salary: int, current_season: int) -> Dictionary:
	"""
	Sign contract with validation.
	Returns: { "success": bool, "error": String, "contract": Contract }
	"""
	# Validate salary cap
	if not can_afford_contract(team_ref, salary):
		var space = get_salary_space(team_ref)
		var overage = salary - space
		var team_id = _get_team_id(team_ref)
		emit_signal("salary_cap_exceeded", team_id, overage)
		
		return {
			"success": false,
			"error": "Salary cap exceeded by %dg (space: %dg, needed: %dg)" % [overage, space, salary],
			"contract": null
		}
	
	# Create and store contract
	var new_contract = Contract.new(character, team_ref, seasons, salary, current_season)
	active_contracts.append(new_contract)
	
	# Remove from free agents
	if character in free_agent_pool:
		free_agent_pool.erase(character)
	
	emit_signal("contract_signed", new_contract)
	
	print("[ContractManager] Signed %s to %s: %d seasons @ %dg" % [
		character.name,
		"Player" if team_ref == null else team_ref.team_name,
		seasons,
		salary
	])
	
	return {
		"success": true,
		"error": "",
		"contract": new_contract
	}

func can_afford_contract(team_ref, salary: int) -> bool:
	return get_salary_space(team_ref) >= salary

func get_salary_space(team_ref) -> int:
	return salary_cap - get_total_salary(team_ref)

func get_total_salary(team_ref) -> int:
	var total = 0
	for contract in active_contracts:
		if _matches_team(contract, team_ref):
			total += contract.salary_per_season
	return total

func get_contracts_for_team(team_ref) -> Array[Contract]:
	var result: Array[Contract] = []
	for contract in active_contracts:
		if _matches_team(contract, team_ref):
			result.append(contract)
	return result

func get_contract_for_character(character) -> Contract:
	for contract in active_contracts:
		if contract.character == character:
			return contract
	return null

func process_contract_expirations() -> Dictionary:
	"""
	Advance all contracts and process expirations.
	
	Returns: {
		"expired_contracts": Array[Contract],
		"player_losses": Array[Character],
		"ai_losses": Array[Character]
	}
	"""
	print("[ContractManager] Processing contract expirations...")
	
	var expired_contracts: Array[Contract] = []
	var player_losses = []
	var ai_losses = []
	
	# Advance and collect expired
	for contract in active_contracts:
		if contract.advance_season():
			expired_contracts.append(contract)
			
			if contract.is_player_contract:
				player_losses.append(contract.character)
			else:
				ai_losses.append(contract.character)
	
	# Remove expired contracts
	for contract in expired_contracts:
		active_contracts.erase(contract)
		free_agent_pool.append(contract.character)
		emit_signal("contract_expired", contract)
		
		print("[ContractManager] Contract expired: %s (was with %s)" % [
			contract.character.name,
			"Your Guild" if contract.is_player_contract else contract.team.team_name
		])
	
	return {
		"expired_contracts": expired_contracts,
		"player_losses": player_losses,
		"ai_losses": ai_losses,
		"total_expired": expired_contracts.size()
	}

## Private helpers

func _matches_team(contract: Contract, team_ref) -> bool:
	if team_ref == null:
		return contract.is_player_contract
	return contract.team == team_ref

func _get_team_id(team_ref) -> String:
	if team_ref == null:
		return "player"
	return String(team_ref.team_id)

func terminate_contract(contract: Contract) -> void:
	"""
	Immediately terminate a contract (for retirement/death/madness).
	Does NOT add character to free agent pool.
	"""
	if contract in active_contracts:
		active_contracts.erase(contract)
		print("[ContractManager] Contract terminated: %s" % contract.character.name)
	else:
		push_warning("[ContractManager] Attempted to terminate non-existent contract for %s" % contract.character.name)
