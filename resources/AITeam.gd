# resources/AITeam.gd
extends Resource
class_name AITeamResource

# Preload AdventurerResource
const AdventurerResource = preload("res://resources/Adventurer.gd")

@export var team_name: String = "Team Alpha"
@export var coach_name: String = "Coach Smith"
@export var team_id: StringName
@export var roster: Array = []  # Array[AdventurerResource] - remove typing for now

# Team personality traits (affects AI behavior and narratives)
@export var aggression: float = 0.5        # 0.0 = defensive, 1.0 = very aggressive
@export var discipline: float = 0.5        # 0.0 = chaotic, 1.0 = organized
@export var experience: float = 0.5        # 0.0 = rookie, 1.0 = veteran
@export var wealth: float = 0.5            # 0.0 = poor, 1.0 = rich (affects draft picks)

# Team colors for UI
@export var primary_color: Color = Color.RED
@export var secondary_color: Color = Color.WHITE

# Performance tracking (for narratives and rivalry system)
@export var seasons_played: int = 0
@export var total_wins: int = 0
@export var total_losses: int = 0
@export var playoff_appearances: int = 0
@export var championships: int = 0
@export var current_season_wins: int = 0
@export var current_season_losses: int = 0

# Draft history for AI behavior
@export var draft_preferences: Dictionary = {}  # role_id -> preference_weight
@export var last_draft_picks: Array = []  # Array[AdventurerResource] - remove typing for now

# Rivalry tracking (team_id -> rivalry_data)
@export var rivalries: Dictionary = {}

# Team strategy tendencies
@export var preferred_formation: String = "balanced"  # balanced, offensive, defensive, etc.
@export var tactical_focus: Array = ["combat", "exploration"]  # what they prioritize

func _init():
	if team_id == StringName():
		team_id = StringName("team_" + str(randi()))

# Calculate team strength for matchmaking
func get_team_strength() -> int:
	var total_strength = 0
	for adventurer in roster:
		total_strength += adventurer.attack + adventurer.defense + adventurer.hp + adventurer.role_stat
	return total_strength

# Get team's average level/experience
func get_team_experience_level() -> float:
	if roster.is_empty():
		return 0.0
	
	var total_exp = 0.0
	for adventurer in roster:
		# Calculate experience based on stats and combat record
		var combat_exp = adventurer.battles_fought * 2 + adventurer.monsters_killed
		var stat_exp = (adventurer.attack + adventurer.defense + adventurer.hp + adventurer.role_stat) / 4.0
		total_exp += combat_exp + stat_exp
	
	return total_exp / roster.size()

# Win rate calculation
func get_win_rate() -> float:
	var total_games = total_wins + total_losses
	if total_games == 0:
		return 0.0
	return float(total_wins) / float(total_games)

# Update rivalry after a match
func update_rivalry(opponent_team_id: StringName, we_won: bool, margin: int):
	if not rivalries.has(opponent_team_id):
		rivalries[opponent_team_id] = {
			"wins": 0,
			"losses": 0,
			"total_matches": 0,
			"intensity": 0.0,  # 0.0 = neutral, 1.0 = heated rivalry
			"last_result": "",
			"biggest_win_margin": 0,
			"biggest_loss_margin": 0
		}
	
	var rivalry = rivalries[opponent_team_id]
	rivalry.total_matches += 1
	
	if we_won:
		rivalry.wins += 1
		rivalry.last_result = "W"
		if margin > rivalry.biggest_win_margin:
			rivalry.biggest_win_margin = margin
	else:
		rivalry.losses += 1
		rivalry.last_result = "L"
		if margin > rivalry.biggest_loss_margin:
			rivalry.biggest_loss_margin = margin
	
	# Update rivalry intensity based on close matches and history
	var match_closeness = 1.0 - (float(margin) / 100.0)  # Closer matches increase intensity
	var history_factor = min(float(rivalry.total_matches) / 10.0, 1.0)  # More matches = more intensity
	rivalry.intensity = min(rivalry.intensity + (match_closeness * 0.1 * history_factor), 1.0)

# Generate team tactics based on personality
func get_battle_tactics() -> Dictionary:
	return {
		"aggression_modifier": aggression * 0.3 - 0.15,  # -0.15 to +0.15
		"formation": preferred_formation,
		"focus_combat": "combat" in tactical_focus,
		"focus_defense": discipline > 0.7,
		"risk_taking": 1.0 - discipline,
		"experience_bonus": experience * 0.1
	}

# Draft AI behavior
func evaluate_prospect(prospect, current_needs: Dictionary) -> float:
	var base_score = 0.0
	
	# Calculate prospect value
	var stat_value = prospect.attack + prospect.defense + prospect.hp + prospect.role_stat
	base_score = float(stat_value) / 4.0
	
	# Apply team personality modifiers
	if aggression > 0.7:
		base_score += prospect.attack * 0.3  # Aggressive teams value attack
	if discipline > 0.7:
		base_score += prospect.defense * 0.3  # Disciplined teams value defense
	
	# Check role preferences
	var role_id = prospect.role.id if prospect.role else StringName()
	if draft_preferences.has(role_id):
		base_score *= draft_preferences.get(role_id, 1.0)
	
	# Apply current needs
	var role_display = prospect.role.display_name if prospect.role else ""
	if current_needs.has(role_display):
		base_score *= current_needs.get(role_display, 1.0)
	
	# Wealth factor (rich teams can afford expensive players)
	var wage_factor = 1.0 - (float(prospect.wage) / 25.0) * (1.0 - wealth)
	base_score *= wage_factor
	
	return base_score

# Update season performance
func record_match_result(won: bool, margin: int = 0):
	if won:
		current_season_wins += 1
		total_wins += 1
	else:
		current_season_losses += 1
		total_losses += 1

# New season reset
func start_new_season():
	seasons_played += 1
	current_season_wins = 0
	current_season_losses = 0
	last_draft_picks.clear()
	
	# Evolve team personality slightly over time
	_evolve_personality()

# Personality evolution based on performance
func _evolve_personality():
	var performance = get_win_rate()
	
	# Successful teams might become more aggressive, unsuccessful more disciplined
	if performance > 0.7:
		aggression = min(aggression + 0.05, 1.0)
		experience = min(experience + 0.03, 1.0)
	elif performance < 0.3:
		discipline = min(discipline + 0.05, 1.0)
		aggression = max(aggression - 0.03, 0.0)
	
	# Clamp values
	aggression = clampf(aggression, 0.0, 1.0)
	discipline = clampf(discipline, 0.0, 1.0)
	experience = clampf(experience, 0.0, 1.0)

# Generate a narrative description of the team
func get_team_description() -> String:
	var desc = "%s, led by %s" % [team_name, coach_name]
	
	# Add personality traits
	if aggression > 0.8:
		desc += ", is known for their aggressive playstyle"
	elif discipline > 0.8:
		desc += ", is famous for their disciplined approach"
	elif experience > 0.8:
		desc += ", brings years of veteran experience"
	
	# Add performance context
	if championships > 0:
		desc += " and has won %d championship%s" % [championships, "s" if championships > 1 else ""]
	elif playoff_appearances > 0:
		desc += " and has made %d playoff appearance%s" % [playoff_appearances, "s" if playoff_appearances > 1 else ""]
	
	return desc + "."

# Generate random AI teams for the league
static func generate_ai_team(team_index: int, difficulty_tier: int = 1) -> AITeamResource:
	var team = AITeamResource.new()
	
	# Generate team names
	var team_names = [
		"Iron Hawks", "Storm Riders", "Void Hunters", "Crystal Guards", "Shadow Wolves",
		"Fire Dragons", "Ice Bears", "Thunder Lions", "Stone Eagles", "Wind Serpents",
		"Blood Ravens", "Silver Stags", "Golden Phoenix", "Dark Owls", "Bright Falcons"
	]
	
	var coach_names = [
		"Marcus Steel", "Elena Frost", "Viktor Stone", "Sara Flame", "Rex Thunder",
		"Luna Silver", "Dante Shadow", "Nova Bright", "Kai Storm", "Zara Wild"
	]
	
	team.team_name = team_names[team_index % team_names.size()]
	team.coach_name = coach_names[team_index % coach_names.size()]
	team.team_id = StringName("ai_team_" + str(team_index))
	
	# Generate personality based on tier and randomness
	team.aggression = randf_range(0.2, 0.9)
	team.discipline = randf_range(0.2, 0.9)
	team.experience = randf_range(0.1, 0.7) + (difficulty_tier * 0.1)
	team.wealth = randf_range(0.3, 0.8) + (difficulty_tier * 0.1)
	
	# Generate team colors
	var colors = [Color.RED, Color.BLUE, Color.GREEN, Color.PURPLE, Color.ORANGE, 
				  Color.CYAN, Color.MAGENTA, Color.YELLOW]
	team.primary_color = colors[team_index % colors.size()]
	team.secondary_color = Color.WHITE if randf() > 0.5 else Color.BLACK
	
	# Set initial draft preferences
	team.draft_preferences = {
		&"tank": randf_range(0.8, 1.2),
		&"damage": randf_range(0.8, 1.2),
		&"healer": randf_range(0.8, 1.2),
		&"navigator": randf_range(0.8, 1.2)
	}
	
	# Set tactical preferences
	if team.aggression > 0.7:
		team.preferred_formation = "offensive"
		team.tactical_focus = ["combat"]
	elif team.discipline > 0.7:
		team.preferred_formation = "defensive"
		team.tactical_focus = ["defense", "exploration"]
	else:
		team.preferred_formation = "balanced"
		team.tactical_focus = ["combat", "exploration"]
	
	return team
