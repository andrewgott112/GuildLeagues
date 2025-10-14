# scripts/systems/ScoutingInfo.gd
extends RefCounted
class_name ScoutingInfo

# ═══════════════════════════════════════════════════════════════════
# STAT KNOWLEDGE CLASS
# ═══════════════════════════════════════════════════════════════════

class StatKnowledge:
	var stat_name: String
	var min_estimate: float
	var max_estimate: float
	var confidence: float = 0.0  # 0.0 to 1.0
	var true_value_known: bool = false
	var experiences: int = 0
	
	func _init(name: String):
		stat_name = name
		min_estimate = 1.0
		max_estimate = 200.0
		confidence = 0.0
	
	func set_range(min_val: float, max_val: float, conf: float):
		"""Set the estimated range and confidence for this stat"""
		min_estimate = min_val
		max_estimate = max_val
		confidence = clampf(conf, 0.0, 1.0)
	
	func get_display_value() -> String:
		"""Get the display string for this stat based on confidence"""
		if confidence >= 0.95 or true_value_known:
			# Show exact value
			return "%.0f" % ((min_estimate + max_estimate) / 2.0)
		elif confidence >= 0.5:
			# Show range
			return "%.0f-%.0f" % [min_estimate, max_estimate]
		else:
			# Unknown
			return "???"
	
	func get_confidence_level() -> String:
		"""Get a text description of confidence level"""
		if confidence >= 0.95:
			return "Confirmed"
		elif confidence >= 0.75:
			return "High confidence"
		elif confidence >= 0.5:
			return "Moderate confidence"
		elif confidence >= 0.25:
			return "Low confidence"
		else:
			return "Unknown"

# ═══════════════════════════════════════════════════════════════════
# REVELATION SPEED CONFIGURATION
# ═══════════════════════════════════════════════════════════════════

const REVELATION_SPEEDS = {
	# Fast reveals (3-5 experiences)
	"hp": {
		"per_experience": 0.15,
		"max_from_scout": 0.4,
	},
	"attack": {
		"per_experience": 0.12,
		"max_from_scout": 0.4,
	},
	
	# Medium reveals (8-12 experiences)
	"defense": {
		"per_experience": 0.08,
		"max_from_scout": 0.35,
	},
	"speed": {
		"per_experience": 0.08,
		"max_from_scout": 0.35,
	},
	"accuracy": {
		"per_experience": 0.08,
		"max_from_scout": 0.35,
	},
	
	# Slow reveals (15-25 experiences)
	"crit_chance": {
		"per_experience": 0.05,
		"max_from_scout": 0.3,
	},
	"role_stat": {
		"per_experience": 0.06,
		"max_from_scout": 0.3,
	},
	"observe_skill": {
		"per_experience": 0.05,
		"max_from_scout": 0.25,
	},
	"decide_skill": {
		"per_experience": 0.05,
		"max_from_scout": 0.25,
	},
	"potential": {
		"per_experience": 0.04,
		"max_from_scout": 0.25,
	},
	
	# Very slow reveals (30+ experiences)
	"injury_prone": {
		"per_experience": 0.03,
		"max_from_scout": 0.2,
	},
	"mental_fortitude": {
		"per_experience": 0.03,
		"max_from_scout": 0.2,
	},
	"loyalty_base": {
		"per_experience": 0.02,
		"max_from_scout": 0.15,
	},
}

# ═══════════════════════════════════════════════════════════════════
# SCOUTING INFO DATA
# ═══════════════════════════════════════════════════════════════════

var character_id: String
var character_name: String  # For easy reference
var base_scouting_level: int = 0

# Per-stat tracking
var stats_known: Dictionary = {}  # stat_name -> StatKnowledge

# Experience counters for different revelation types
var combat_experiences: int = 0
var damage_taken_experiences: int = 0
var damage_dealt_experiences: int = 0
var training_sessions: int = 0
var seasons_observed: int = 0
var injuries_seen: int = 0
var battles_survived: int = 0
var high_pressure_moments: int = 0

# Last observation date (for decay)
var last_observed_season: int = 0
var last_observed_week: int = 0

# ═══════════════════════════════════════════════════════════════════
# INITIALIZATION
# ═══════════════════════════════════════════════════════════════════

func _init(char_name: String):
	character_id = char_name  # Using name as ID for now
	character_name = char_name
	initialize_all_stats()

func initialize_all_stats():
	"""Initialize tracking for all stats"""
	var all_stats = [
		"attack", "defense", "hp", "speed", "accuracy", "crit_chance",
		"role_stat", "observe_skill", "decide_skill",
		"potential", "injury_prone", "mental_fortitude", "loyalty_base"
	]
	
	for stat in all_stats:
		stats_known[stat] = StatKnowledge.new(stat)

# ═══════════════════════════════════════════════════════════════════
# SCOUT APPLICATION
# ═══════════════════════════════════════════════════════════════════

func apply_scout_level(level: int, character: AdventurerResource):
	"""Apply initial scouting information based on scout quality"""
	base_scouting_level = level
	
	if level == 0:
		# No scout - everything unknown
		return
	
	# For each stat, set initial range based on scout level
	for stat_name in stats_known.keys():
		var stat = stats_known[stat_name]
		var true_value = character.get(stat_name)
		
		var config = REVELATION_SPEEDS.get(stat_name, {"max_from_scout": 0.3})
		var max_confidence = config["max_from_scout"]
		
		# Scout level determines initial confidence (0.15 to max_confidence)
		var confidence = lerpf(0.15, max_confidence, level / 4.0)
		
		# Calculate initial range based on confidence
		var range_width = lerpf(100.0, 20.0, confidence)
		
		stat.min_estimate = max(1.0, true_value - range_width / 2.0)
		stat.max_estimate = min(200.0, true_value + range_width / 2.0)
		stat.confidence = confidence

func apply_scout_with_stats(scout_character: AdventurerResource, prospect: AdventurerResource):
	"""Apply scouting based on scout's own stats (better at evaluating similar stats)"""
	
	# Base level from scout's observation skill
	var base_level = int(scout_character.observe_skill / 50.0)  # 0-4 range
	apply_scout_level(base_level, prospect)
	
	# Bonus accuracy for stats the scout excels at
	for stat_name in stats_known.keys():
		if stat_name in ["attack", "defense", "hp", "speed", "crit_chance", "accuracy"]:
			var scout_stat_value = scout_character.get(stat_name)
			
			# If scout has high value in this stat, they're better at evaluating it
			if scout_stat_value >= 140:
				tighten_stat_range(stat_name, 10)  # Reduce uncertainty by 10
			elif scout_stat_value >= 120:
				tighten_stat_range(stat_name, 5)

# ═══════════════════════════════════════════════════════════════════
# CONTEXT-DEPENDENT REVELATION
# ═══════════════════════════════════════════════════════════════════

func reveal_from_damage_taken(damage: float, character: AdventurerResource):
	"""Reveal defense and HP from taking damage"""
	reveal_stat("defense", 1.0, character)
	reveal_stat("hp", 0.8, character)
	damage_taken_experiences += 1
	update_last_observed()

func reveal_from_damage_dealt(damage: float, was_crit: bool, character: AdventurerResource):
	"""Reveal attack and crit chance from dealing damage"""
	reveal_stat("attack", 1.0, character)
	reveal_stat("accuracy", 0.7, character)
	if was_crit:
		reveal_stat("crit_chance", 1.5, character)  # Crits are high-quality data
	damage_dealt_experiences += 1
	update_last_observed()

func reveal_from_near_death_survival(character: AdventurerResource):
	"""Surviving at low HP reveals mental fortitude"""
	reveal_stat("mental_fortitude", 2.0, character)
	high_pressure_moments += 1
	update_last_observed()

func reveal_from_training_session(stat_gain: float, character: AdventurerResource):
	"""Training reveals potential"""
	var quality = clampf(stat_gain / 2.0, 0.5, 2.0)  # Better gain = better data
	reveal_stat("potential", quality, character)
	training_sessions += 1
	update_last_observed()

func reveal_from_combat(character: AdventurerResource):
	"""General combat experience reveals various stats"""
	# Each combat reveals a bit about multiple stats
	reveal_stat("attack", 0.5, character)
	reveal_stat("defense", 0.5, character)
	reveal_stat("hp", 0.5, character)
	reveal_stat("speed", 0.6, character)
	combat_experiences += 1
	battles_survived += 1
	update_last_observed()

func reveal_from_injury(character: AdventurerResource):
	"""Getting injured reveals injury proneness"""
	reveal_stat("injury_prone", 1.5, character)
	injuries_seen += 1
	update_last_observed()

func reveal_from_avoiding_injury(character: AdventurerResource):
	"""Not getting injured over time also reveals injury proneness (slowly)"""
	if battles_survived >= 10:
		reveal_stat("injury_prone", 0.3, character)
		update_last_observed()

func reveal_from_decision_making(character: AdventurerResource):
	"""Observing decision-making reveals decide_skill"""
	reveal_stat("decide_skill", 0.8, character)
	update_last_observed()

func reveal_from_observation(character: AdventurerResource):
	"""Observing their observations reveals observe_skill"""
	reveal_stat("observe_skill", 0.8, character)
	update_last_observed()

# ═══════════════════════════════════════════════════════════════════
# CORE REVELATION LOGIC
# ═══════════════════════════════════════════════════════════════════

func reveal_stat(stat_name: String, context_quality: float, character: AdventurerResource):
	"""Core function to reveal a stat based on context quality"""
	if not stats_known.has(stat_name):
		return
	
	var stat = stats_known[stat_name]
	var speed_config = REVELATION_SPEEDS.get(stat_name, {"per_experience": 0.05})
	
	# Calculate confidence gain
	var confidence_gain = speed_config["per_experience"] * context_quality
	stat.confidence = minf(1.0, stat.confidence + confidence_gain)
	stat.experiences += 1
	
	# Narrow the range toward true value
	narrow_stat_range_to_true(stat, character)

func narrow_stat_range_to_true(stat: StatKnowledge, character: AdventurerResource):
	"""Narrow the stat range toward the true value as confidence increases"""
	var true_value = character.get(stat.stat_name)
	var current_mid = (stat.min_estimate + stat.max_estimate) / 2.0
	
	# Interpolate mid-point toward true value
	var new_mid = lerpf(current_mid, true_value, stat.confidence * 0.15)
	
	# Calculate new range width (starts wide, ends narrow)
	var new_range_width = lerpf(100.0, 5.0, stat.confidence)
	
	stat.min_estimate = max(1.0, new_mid - new_range_width / 2.0)
	stat.max_estimate = min(200.0, new_mid + new_range_width / 2.0)
	
	# At 95% confidence, lock in true value
	if stat.confidence >= 0.95:
		stat.min_estimate = true_value
		stat.max_estimate = true_value
		stat.true_value_known = true

func tighten_stat_range(stat_name: String, amount: float):
	"""Manually tighten a stat range (used for scout bonuses)"""
	if not stats_known.has(stat_name):
		return
	
	var stat = stats_known[stat_name]
	var current_width = stat.max_estimate - stat.min_estimate
	var new_width = max(5.0, current_width - amount)
	
	var mid = (stat.min_estimate + stat.max_estimate) / 2.0
	stat.min_estimate = mid - new_width / 2.0
	stat.max_estimate = mid + new_width / 2.0

# ═══════════════════════════════════════════════════════════════════
# KNOWLEDGE DECAY
# ═══════════════════════════════════════════════════════════════════

func apply_knowledge_decay(seasons_absent: int):
	"""Apply knowledge decay for characters not observed"""
	if seasons_absent <= 0:
		return
	
	for stat in stats_known.values():
		if stat.true_value_known:
			continue  # Don't decay confirmed values
		
		# Different decay rates for different stat types
		var decay_rate = 0.1  # Default 10% per season
		
		# Slower decay for physical traits
		if stat.stat_name in ["injury_prone", "peak_age"]:
			decay_rate = 0.05
		# Faster decay for mental/personality
		elif stat.stat_name in ["loyalty_base", "mental_fortitude"]:
			decay_rate = 0.2
		
		# Apply decay
		stat.confidence = maxf(0.1, stat.confidence - (decay_rate * seasons_absent))
		
		# Widen range as confidence drops
		if stat.confidence < 0.5:
			var center = (stat.min_estimate + stat.max_estimate) / 2.0
			var current_width = stat.max_estimate - stat.min_estimate
			var new_width = current_width * (1.0 + 0.2 * seasons_absent)
			
			stat.min_estimate = max(1.0, center - new_width / 2.0)
			stat.max_estimate = min(200.0, center + new_width / 2.0)

# ═══════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

func update_last_observed():
	"""Update the last observation timestamp (call from Game context)"""
	if Game:
		last_observed_season = Game.season
		# Note: You'll need to add week tracking if you implement weekly activities

func get_overall_confidence() -> float:
	"""Get average confidence across all stats"""
	if stats_known.is_empty():
		return 0.0
	
	var total = 0.0
	for stat in stats_known.values():
		total += stat.confidence
	return total / stats_known.size()

func get_stat_display(stat_name: String) -> String:
	"""Get display string for a specific stat"""
	if stats_known.has(stat_name):
		return stats_known[stat_name].get_display_value()
	return "???"

func is_stat_known(stat_name: String, threshold: float = 0.5) -> bool:
	"""Check if a stat is known above a certain confidence threshold"""
	if stats_known.has(stat_name):
		return stats_known[stat_name].confidence >= threshold
	return false
