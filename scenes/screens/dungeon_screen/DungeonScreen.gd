# scenes/screens/dungeon_screen/DungeonScreen.gd
extends Control

const DungeonGenerator = preload("res://scripts/systems/dungeon_generator.gd")
const DungeonResource = preload("res://resources/Dungeon.gd")
const VisualExploration = preload("res://scripts/systems/visual_exploration.gd")
const MonsterResource = preload("res://resources/Monster.gd")

@onready var dungeon_grid: GridContainer = $Margin/Column/DungeonPanel/ScrollContainer/GridContainer
@onready var dungeon_info: Label = $Margin/Column/TopBar/DungeonInfo
@onready var party_info: Label = $Margin/Column/TopBar/PartyInfo
@onready var generate_btn: Button = $Margin/Column/BottomBar/GenerateBtn
@onready var explore_btn: Button = $Margin/Column/BottomBar/ExploreBtn
@onready var back_btn: Button = $Margin/Column/BottomBar/BackBtn
@onready var generation_options: OptionButton = $Margin/Column/BottomBar/GenerationOptions

var current_dungeon: DungeonResource
var generator: DungeonGenerator
var visual_explorer: VisualExploration
var tile_buttons: Array = []

# Exploration state
var exploration_timer: Timer
var total_gold_found: int = 0
var total_gold_collected: int = 0  # NEW: Track actual gold collected vs left behind

# Battle system integration
var battle_window_scene = preload("res://scenes/ui/BattleWindow.tscn")
var current_battle_window = null
var exploration_paused: bool = false

const TILE_SIZE = 32

func _ready():
	print("DungeonScreen: Starting...")
	
	# Create components
	generator = DungeonGenerator.new()
	visual_explorer = VisualExploration.new()
	
	# Create exploration timer
	exploration_timer = Timer.new()
	exploration_timer.wait_time = 0.8
	exploration_timer.one_shot = false
	exploration_timer.timeout.connect(_on_exploration_timer)
	add_child(exploration_timer)
	
	# Connect visual exploration signals
	visual_explorer.exploration_step_complete.connect(_on_step_complete)
	visual_explorer.exploration_finished.connect(_on_exploration_finished)
	visual_explorer.monster_encounter.connect(_on_monster_encounter)  # NEW: Monster encounter signal
	
	# Setup UI
	_setup_generation_options()
	_connect_buttons()
	_generate_new_dungeon()
	
	print("DungeonScreen: Ready!")

func _setup_generation_options():
	generation_options.add_item("Simple Rooms", DungeonGenerator.GenerationType.SIMPLE_ROOMS)
	generation_options.add_item("Cave System", DungeonGenerator.GenerationType.CELLULAR_AUTOMATA)
	generation_options.add_item("Maze", DungeonGenerator.GenerationType.MAZE)
	generation_options.add_item("Mixed", DungeonGenerator.GenerationType.MIXED)

func _connect_buttons():
	generate_btn.pressed.connect(_on_generate_pressed)
	explore_btn.pressed.connect(_on_explore_pressed)
	back_btn.pressed.connect(_on_back_pressed)

func _generate_new_dungeon():
	print("Generating new dungeon...")
	
	var gen_type = generation_options.get_selected_id()
	var difficulty = _calculate_difficulty()
	
	current_dungeon = generator.generate_dungeon(
		20, 15,
		difficulty,
		gen_type as DungeonGenerator.GenerationType,
		randi()
	)
	
	current_dungeon.name = _generate_dungeon_name()
	
	# Reset exploration state
	total_gold_found = 0
	total_gold_collected = 0
	exploration_timer.stop()
	exploration_paused = false
	
	# Create new visual explorer
	visual_explorer = VisualExploration.new()
	visual_explorer.exploration_step_complete.connect(_on_step_complete)
	visual_explorer.exploration_finished.connect(_on_exploration_finished)
	visual_explorer.monster_encounter.connect(_on_monster_encounter)  # NEW: Connect monster signal
	
	_update_display()
	print("Generated: " + current_dungeon.name)

func _calculate_difficulty() -> int:
	var base_difficulty = Game.season
	
	if Game.roster.size() > 0:
		var avg_power = 0
		for adventurer in Game.roster:
			avg_power += adventurer.attack + adventurer.defense + adventurer.role_stat
		avg_power = avg_power / Game.roster.size() / 10
		base_difficulty += avg_power
	
	return clampi(base_difficulty, 1, 10)

func _generate_dungeon_name() -> String:
	var prefixes = ["Ancient", "Forgotten", "Dark", "Cursed", "Lost", "Hidden", "Sunken", "Frozen"]
	var suffixes = ["Caverns", "Ruins", "Depths", "Catacombs", "Chambers", "Tunnels", "Halls", "Sanctuary"]
	return "%s %s" % [prefixes.pick_random(), suffixes.pick_random()]

func _update_display():
	_update_dungeon_info()
	_update_party_info()
	_build_dungeon_grid()
	_update_explore_button()

func _update_dungeon_info():
	var monster_count = current_dungeon.count_tiles_of_type(DungeonTileResource.MONSTER)
	var treasure_count = current_dungeon.count_tiles_of_type(DungeonTileResource.TREASURE)
	
	var info_text = "%s (Difficulty: %d)\nMonsters: %d | Treasure: %d" % [
		current_dungeon.name,
		current_dungeon.difficulty_level,
		monster_count,
		treasure_count
	]
	
	if exploration_paused:
		info_text += "\n--- COMBAT IN PROGRESS ---"
	elif visual_explorer.is_exploring():
		var summary = visual_explorer.get_exploration_summary()
		info_text += "\n--- EXPLORING ---"
		info_text += "\nSteps: %d | Tiles: %d" % [summary.moves_made, summary.tiles_explored]
		info_text += "\nGold: %d/%d" % [summary.gold_carried, summary.gold_capacity]
		
		# NEW: Show exit status
		if summary.exit_found:
			info_text += " | Exit found"
		if summary.decided_to_exit:
			info_text += " | Heading to exit"
			
	elif visual_explorer.is_finished():
		var summary = visual_explorer.get_exploration_summary()
		info_text += "\n--- EXPLORATION COMPLETE ---"
		info_text += "\nTotal Steps: %d | Gold Collected: %d" % [summary.moves_made, total_gold_collected]
		
		# Show efficiency if we have the data
		if "exploration_efficiency" in summary:
			info_text += "\nEfficiency: %.1f%%" % (summary.exploration_efficiency * 100)
	
	dungeon_info.text = info_text

func _update_party_info():
	if Game.roster.is_empty():
		party_info.text = "No party assembled"
		return
	
	var total_attack = 0
	var total_defense = 0
	var total_hp = 0
	var navigation_score = 0
	
	for adventurer in Game.roster:
		total_attack += adventurer.attack
		total_defense += adventurer.defense
		total_hp += adventurer.hp
		
		# Calculate navigation contribution
		if adventurer.role and str(adventurer.role.role_stat_name).to_lower() in ["navigation", "navigate"]:
			navigation_score += adventurer.role_stat * 2
		else:
			navigation_score += max(1, adventurer.role_stat / 2)
	
	navigation_score += Game.roster.size() * 2
	
	var party_stats = "Party (%d): ATK %d | DEF %d | HP %d" % [
		Game.roster.size(), total_attack, total_defense, total_hp
	]
	
	var nav_rating = "Poor"
	if navigation_score >= 40: nav_rating = "Excellent"
	elif navigation_score >= 25: nav_rating = "Good"
	elif navigation_score >= 15: nav_rating = "Average"
	
	var nav_info = "Navigation: %s (%d)" % [nav_rating, navigation_score]
	
	# NEW: Add carrying capacity info
	nav_info += "\nCarrying Capacity: 100g"  # v0.1 flat cap
	
	if visual_explorer.is_exploring():
		var party_pos = visual_explorer.get_party_position()
		nav_info += "\nPosition: (%d, %d)" % [party_pos.x, party_pos.y]
	
	party_info.text = party_stats + "\n" + nav_info

func _update_explore_button():
	if Game.roster.is_empty():
		explore_btn.disabled = true
		explore_btn.text = "Need Party"
	elif exploration_paused:
		explore_btn.disabled = true
		explore_btn.text = "Combat Active"
	elif visual_explorer.is_exploring():
		explore_btn.disabled = true
		explore_btn.text = "Exploring..."
	elif visual_explorer.is_finished():
		explore_btn.disabled = true
		explore_btn.text = "Explored"
	else:
		explore_btn.disabled = false
		explore_btn.text = "Explore Dungeon"

func _build_dungeon_grid():
	# Clear existing buttons
	for button in tile_buttons:
		if is_instance_valid(button):
			button.queue_free()
	tile_buttons.clear()
	
	# Setup grid
	dungeon_grid.columns = current_dungeon.width
	
	# Create tile buttons
	for y in current_dungeon.height:
		for x in current_dungeon.width:
			var tile = current_dungeon.get_tile(x, y)
			var button = _create_tile_button(tile, x, y)
			dungeon_grid.add_child(button)
			tile_buttons.append(button)

func _create_tile_button(tile, x: int, y: int) -> Button:
	var button = Button.new()
	button.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	
	var tile_pos = Vector2i(x, y)
	var is_party_pos = false
	var is_visited = false
	
	# Check exploration state
	if visual_explorer.is_exploring() or visual_explorer.is_finished():
		var party_position = visual_explorer.get_party_position()
		var visited_tiles = visual_explorer.get_visited_tiles()
		
		is_party_pos = (tile_pos == party_position and visual_explorer.is_exploring())
		is_visited = tile_pos in visited_tiles
	
	# Determine button text and color
	var button_text = tile.get_display_char()
	var button_color = tile.get_display_color()
	
	# Override display for cleared tiles
	if tile.cleared and tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.MONSTER, DungeonTileResource.BOSS]:
		match tile.tile_type:
			DungeonTileResource.TREASURE:
				button_text = "t"
				button_color = Color.GRAY
			DungeonTileResource.MONSTER:
				button_text = "m"
				button_color = Color.DARK_GRAY
			DungeonTileResource.BOSS:
				button_text = "b"
				button_color = Color.DARK_GRAY
	
	if is_party_pos:
		button_text = "P"
		button_color = Color.CYAN
	elif is_visited:
		button_color = button_color.lightened(0.3)
	elif visual_explorer.is_exploring() and not is_visited:
		button_color = button_color.darkened(0.6)
	
	# Style the button
	var style = StyleBoxFlat.new()
	style.bg_color = button_color
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_color = Color.BLACK
	
	button.text = button_text
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	
	# Set tooltip
	var tooltip = _get_tile_tooltip(tile)
	if tile.cleared and tile.tile_type in [DungeonTileResource.TREASURE, DungeonTileResource.MONSTER, DungeonTileResource.BOSS]:
		tooltip += "\n(Cleared)"
	elif is_visited: 
		tooltip += "\n(Explored)"
	elif visual_explorer.is_exploring(): 
		tooltip += "\n(Unexplored)"
	button.tooltip_text = tooltip
	
	# Disable walls
	if tile.tile_type == DungeonTileResource.WALL:
		button.disabled = true
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	return button

func _get_tile_tooltip(tile) -> String:
	match tile.tile_type:
		DungeonTileResource.WALL:
			return "Wall"
		DungeonTileResource.EMPTY:
			return "Empty room"
		DungeonTileResource.ENTRANCE:
			return "Dungeon entrance"
		DungeonTileResource.EXIT:
			if tile.cleared:
				return "Dungeon exit (bonus claimed)"
			else:
				return "Dungeon exit"
		DungeonTileResource.TREASURE:
			if tile.cleared:
				return "Empty treasure chest (already looted)"
			else:
				return "Treasure room\nValue: %d gold" % tile.treasure_value
		DungeonTileResource.MONSTER:
			if tile.cleared:
				return "Empty monster lair (already cleared)"
			else:
				return "Monster encounter\nLevel: %d | Count: %d" % [tile.monster_level, tile.monster_count]
		DungeonTileResource.BOSS:
			if tile.cleared:
				return "Boss chamber (already defeated)"
			else:
				return "Boss encounter\nLevel: %d" % tile.monster_level
		_:
			return "Unknown"

# Button event handlers
func _on_generate_pressed():
	_generate_new_dungeon()

func _on_explore_pressed():
	if Game.roster.is_empty():
		print("No party to explore with!")
		return
		
	if visual_explorer.is_exploring() or visual_explorer.is_finished() or exploration_paused:
		print("Already exploring, finished, or in combat!")
		return
	
	print("Starting visual exploration...")
	
	if visual_explorer.start_exploration(current_dungeon, Game.roster):
		total_gold_found = 0
		total_gold_collected = 0
		exploration_timer.start()
		_update_display()
		print("Visual exploration started!")
	else:
		print("Failed to start exploration!")

func _on_back_pressed():
	if exploration_timer:
		exploration_timer.stop()
	
	# Close any active battle window
	if current_battle_window:
		current_battle_window.queue_free()
		current_battle_window = null
	
	Game.goto(Game.Phase.GUILD)
	get_tree().change_scene_to_file("res://scenes/screens/guild_screen/guild_screen.tscn")

# Visual exploration integration
func _on_exploration_timer():
	if not visual_explorer.is_exploring() or exploration_paused:
		exploration_timer.stop()
		return
	
	var step_result = visual_explorer.step_exploration()
	
	if visual_explorer.is_finished():
		exploration_timer.stop()

# NEW: Monster encounter handler
func _on_monster_encounter(encounter_data: Dictionary):
	"""Handle when the exploration encounters a monster"""
	print("Monster encounter triggered!")
	print("Encounter data: ", encounter_data)
	
	# Pause exploration
	exploration_paused = true
	exploration_timer.stop()
	
	# Generate monsters for the encounter
	var monsters = []
	var monster_count = encounter_data.get("monster_count", 1)
	var monster_level = encounter_data.get("monster_level", 1)
	
	for i in monster_count:
		var monster = MonsterResource.generate_random_monster(monster_level)
		monsters.append(monster)
		print("Generated monster: %s (Level %d)" % [monster.name, monster.level])
	
	# Create and show battle window
	current_battle_window = battle_window_scene.instantiate()
	add_child(current_battle_window)
	
	# Setup the battle
	var encounter_name = "Dungeon Encounter"
	if monster_count == 1:
		encounter_name = "vs %s" % monsters[0].name
	else:
		encounter_name = "vs %d Monsters" % monster_count
	
	current_battle_window.setup_battle(Game.roster, monsters, encounter_name)
	current_battle_window.battle_window_closed.connect(_on_battle_finished)
	current_battle_window.show_battle()
	
	_update_display()

func _on_battle_finished(battle_result: Dictionary):
	"""Handle when a battle is finished"""
	print("Battle finished with result: ", battle_result)
	
	# Clean up battle window
	if current_battle_window:
		current_battle_window.queue_free()
		current_battle_window = null
	
	# Resume exploration
	exploration_paused = false
	
	# Tell the visual explorer the battle result
	if visual_explorer:
		visual_explorer.resolve_monster_encounter(battle_result)
	
	# Resume exploration timer if still exploring
	if visual_explorer.is_exploring():
		exploration_timer.start()
	
	_update_display()

func _on_step_complete(result: Dictionary):
	print("Exploration step: %s" % result.message)
	
	# NEW: Handle gold collection vs gold found
	if result.gold_found > 0:
		total_gold_found += result.gold_found
		
		if result.has("gold_collected"):
			total_gold_collected += result.gold_collected
			Game.gold += result.gold_collected
			print("Found %d gold, collected %d! (Total collected: %d)" % [result.gold_found, result.gold_collected, total_gold_collected])
			
			if result.has("gold_left_behind") and result.gold_left_behind > 0:
				print("Left %d gold behind due to carrying capacity!" % result.gold_left_behind)
		else:
			# Fallback for old format
			total_gold_collected += result.gold_found
			Game.gold += result.gold_found
			print("Found %d gold! (Total: %d)" % [result.gold_found, total_gold_collected])
	
	# Handle bonus gold
	if result.bonus_gold > 0:
		total_gold_collected += result.bonus_gold
		Game.gold += result.bonus_gold
		print("Bonus gold: %d!" % result.bonus_gold)
	
	# Update visual display
	_update_display()

func _on_exploration_finished(final_result: Dictionary):
	print("\n=== EXPLORATION COMPLETE ===")
	print("Total moves: %d" % final_result.total_moves)
	print("Tiles explored: %d" % final_result.tiles_explored)
	print("Exploration efficiency: %.1f%%" % (final_result.exploration_efficiency * 100))
	print("Total gold collected: %d" % total_gold_collected)
	
	# NEW: Show exit reason
	if final_result.has("exit_reason"):
		print("Exit reason: %s" % final_result.exit_reason)
	if final_result.has("early_exit") and final_result.early_exit:
		print("Early exit: Yes")
	
	print("============================\n")
	
	_update_display()
