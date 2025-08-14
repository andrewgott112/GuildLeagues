extends AcceptDialog

const BattleSystem = preload("res://scripts/systems/battle_system.gd")

# UI References - found manually in _ready
var battle_title: Label
var battle_status: Label
var players_list: VBoxContainer
var enemies_list: VBoxContainer
var log_text: RichTextLabel
var start_battle_btn: Button
var close_btn: Button

# Battle data
var battle_system: BattleSystem
var player_party: Array = []
var enemy_monsters: Array = []
var battle_finished: bool = false
var update_timer: Timer

# UI tracking
var player_cards: Dictionary = {}  # combatant_name -> card_node
var enemy_cards: Dictionary = {}   # combatant_name -> card_node

signal battle_window_closed(result: Dictionary)

func _ready():
	print("BattleWindow _ready() called")
	
	# Wait for scene to load
	await get_tree().process_frame
	
	# Find UI nodes
	_find_ui_nodes()
	
	# Connect signals
	if start_battle_btn:
		start_battle_btn.pressed.connect(_on_start_battle_pressed)
	if close_btn:
		close_btn.pressed.connect(_on_close_pressed)
	close_requested.connect(_on_close_pressed)
	
	# Create battle system
	battle_system = BattleSystem.new()
	add_child(battle_system)
	
	# Create timer for UI updates
	update_timer = Timer.new()
	update_timer.wait_time = 0.1
	update_timer.timeout.connect(_update_display)
	add_child(update_timer)
	
	# Connect ALL battle signals for real-time updates
	battle_system.battle_started.connect(_on_battle_started)
	battle_system.battle_finished.connect(_on_battle_finished)
	battle_system.phase_changed.connect(_on_phase_changed)
	battle_system.action_completed.connect(_on_action_completed)
	battle_system.combatant_died.connect(_on_combatant_died)
	
	print("BattleWindow ready!")

func _find_ui_nodes():
	"""Find all UI nodes"""
	battle_title = find_child("BattleTitle", true, false)
	battle_status = find_child("BattleStatus", true, false)
	players_list = find_child("PlayersList", true, false)
	enemies_list = find_child("EnemiesList", true, false)
	log_text = find_child("LogText", true, false)
	start_battle_btn = find_child("StartBattleBtn", true, false)
	close_btn = find_child("CloseBtn", true, false)
	
	print("Found UI nodes: title=%s, players=%s, enemies=%s, log=%s" % [
		str(battle_title != null),
		str(players_list != null), 
		str(enemies_list != null),
		str(log_text != null)
	])

func setup_battle(party: Array, monsters: Array, encounter_name: String = "Combat"):
	"""Setup the battle"""
	print("Setting up battle: %s" % encounter_name)
	
	player_party = party.duplicate()
	enemy_monsters = monsters.duplicate()
	battle_finished = false
	
	# Clear tracking
	player_cards.clear()
	enemy_cards.clear()
	
	# Set UI
	if battle_title:
		battle_title.text = encounter_name
	if battle_status:
		battle_status.text = "Press 'Start Battle' to begin"
	if start_battle_btn:
		start_battle_btn.disabled = false
		start_battle_btn.text = "Start Battle"
	
	# Setup log
	if log_text:
		log_text.clear()
		_log_battle("🏛️ %s" % encounter_name)
		_log_battle("⚔️ Party (%d) vs Enemies (%d)" % [party.size(), monsters.size()])
		_log_battle("📋 Ready to fight!")
	
	# Create combatant cards
	_create_combatant_cards()

func _create_combatant_cards():
	"""Create detailed combatant cards with health bars"""
	print("Creating combatant cards...")
	
	# Clear existing
	if players_list:
		for child in players_list.get_children():
			child.queue_free()
	if enemies_list:
		for child in enemies_list.get_children():
			child.queue_free()
	
	# Wait for cleanup
	await get_tree().process_frame
	
	# Add player cards
	if players_list:
		for adventurer in player_party:
			var card = _create_detailed_card(adventurer.name, adventurer, true)
			players_list.add_child(card)
			player_cards[adventurer.name] = card
		print("Added %d player cards" % players_list.get_child_count())
	
	# Add enemy cards
	if enemies_list:
		for monster in enemy_monsters:
			var card = _create_detailed_card(monster.name, monster, false)
			enemies_list.add_child(card)
			enemy_cards[monster.name] = card
		print("Added %d enemy cards" % enemies_list.get_child_count())
	
	# Force scroll container sizes
	_set_scroll_sizes()

func _create_detailed_card(name: String, data, is_player: bool) -> Panel:
	"""Create a detailed combatant card with health and status"""
	var card = Panel.new()
	card.custom_minimum_size = Vector2(250, 80)
	card.name = name + "_Card"
	
	# Style
	var style = StyleBoxFlat.new()
	if is_player:
		style.bg_color = Color(0.2, 0.4, 0.2, 0.9)
		style.border_color = Color(0.4, 0.8, 0.4)
	else:
		style.bg_color = Color(0.4, 0.2, 0.2, 0.9)
		style.border_color = Color(0.8, 0.4, 0.4)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	card.add_theme_stylebox_override("panel", style)
	
	# Main container
	var vbox = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)
	
	# Top margin
	var top_margin = MarginContainer.new()
	top_margin.add_theme_constant_override("margin_left", 8)
	top_margin.add_theme_constant_override("margin_right", 8)
	top_margin.add_theme_constant_override("margin_top", 6)
	top_margin.add_theme_constant_override("margin_bottom", 6)
	vbox.add_child(top_margin)
	
	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 3)
	top_margin.add_child(content_vbox)
	
	# Name label
	var name_label = Label.new()
	name_label.text = name
	name_label.name = "NameLabel"
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_font_size_override("font_size", 14)
	content_vbox.add_child(name_label)
	
	# Health info
	var health_hbox = HBoxContainer.new()
	health_hbox.add_theme_constant_override("separation", 6)
	content_vbox.add_child(health_hbox)
	
	var health_label = Label.new()
	health_label.name = "HealthLabel"
	var current_hp = data.current_hp if data.has_method("get_current_hp") else (data.hp if "hp" in data else 100)
	var max_hp = data.max_hp if data.has_method("get_max_hp") else (data.hp if "hp" in data else 100)
	health_label.text = "HP: %d/%d" % [current_hp, max_hp]
	health_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	health_label.add_theme_font_size_override("font_size", 11)
	health_hbox.add_child(health_label)
	
	# Health bar
	var health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(100, 8)
	health_bar.max_value = max_hp
	health_bar.value = current_hp
	health_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	health_hbox.add_child(health_bar)
	
	# Status label
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "Ready"
	status_label.add_theme_color_override("font_color", Color.CYAN)
	status_label.add_theme_font_size_override("font_size", 10)
	content_vbox.add_child(status_label)
	
	return card

func _set_scroll_sizes():
	"""Set minimum sizes for scroll containers"""
	var players_scroll = find_child("PlayersScroll", true, false)
	var enemies_scroll = find_child("EnemyScroll", true, false)
	
	if players_scroll:
		players_scroll.custom_minimum_size = Vector2(0, 150)
	if enemies_scroll:
		enemies_scroll.custom_minimum_size = Vector2(0, 150)

func _on_start_battle_pressed():
	"""Start battle"""
	print("Starting battle...")
	
	if battle_system.start_battle(player_party, enemy_monsters):
		if start_battle_btn:
			start_battle_btn.disabled = true
			start_battle_btn.text = "Fighting..."
		if battle_status:
			battle_status.text = "Battle in progress!"
		update_timer.start()
		_log_battle("⚔️ Battle begins!")
	else:
		_log_battle("❌ Failed to start battle")

func _on_battle_started():
	"""Battle started"""
	_log_battle("🎯 All combatants ready!")
	_update_all_cards()

func _on_phase_changed(combatant_name: String, phase: String):
	"""Update combatant status when phase changes"""
	_log_battle("👁️ %s is %s" % [combatant_name, phase])
	_update_combatant_status(combatant_name, phase)

func _on_action_completed(combatant_name: String, action: String, result: Dictionary):
	"""Handle completed actions"""
	var message = "⚡ %s performed %s" % [combatant_name, action]
	
	if result.has("target") and result.has("damage"):
		message += " on %s for %d damage" % [result.target, result.damage]
		if result.get("target_defeated", false):
			message += " 💀"
	elif result.has("message"):
		message += " (%s)" % result.message
	
	_log_battle(message)
	_update_all_cards()

func _on_combatant_died(combatant_name: String):
	"""Handle combatant death"""
	_log_battle("💀 %s has been defeated!" % combatant_name)
	_update_combatant_card(combatant_name)

func _on_battle_finished(result: Dictionary):
	"""Battle finished"""
	battle_finished = true
	update_timer.stop()
	
	if result.get("victory", false):
		_log_battle("🎉 VICTORY!")
		if battle_status:
			battle_status.text = "Victory! All enemies defeated!"
	else:
		_log_battle("💀 DEFEAT!")
		if battle_status:
			battle_status.text = "Defeat! Party was overwhelmed!"
	
	# Final update of all cards
	_update_all_cards()
	
	if close_btn:
		close_btn.text = "Continue"
		close_btn.disabled = false

func _on_close_pressed():
	"""Close window"""
	print("Closing battle window")
	
	if battle_system and battle_system.is_battle_active():
		battle_system.force_end_battle()
	
	var result = {
		"completed": battle_finished, 
		"victory": battle_finished  # For now, assume completion means victory
	}
	
	battle_window_closed.emit(result)
	hide()

func _update_display():
	"""Update display during battle"""
	if battle_system and battle_system.is_battle_active():
		_update_all_cards()

func _update_all_cards():
	"""Update all combatant cards"""
	if not battle_system:
		return
	
	var combatants = battle_system.get_combatants()
	for combatant in combatants:
		_update_combatant_card(combatant.name)

func _update_combatant_card(combatant_name: String):
	"""Update a specific combatant's card"""
	var card = null
	
	# Find the card
	if combatant_name in player_cards:
		card = player_cards[combatant_name]
	elif combatant_name in enemy_cards:
		card = enemy_cards[combatant_name]
	
	if not card:
		return
	
	# Find the combatant data
	var combatant_data = null
	if battle_system:
		var combatants = battle_system.get_combatants()
		for combatant in combatants:
			if combatant.name == combatant_name:
				combatant_data = combatant
				break
	
	if not combatant_data:
		return
	
	# Update health
	var health_label = card.find_child("HealthLabel", true, false)
	var health_bar = card.find_child("HealthBar", true, false)
	
	if health_label and health_bar:
		var current_hp = combatant_data.get_current_hp()
		var max_hp = combatant_data.get_max_hp()
		
		health_label.text = "HP: %d/%d" % [current_hp, max_hp]
		health_bar.value = current_hp
		
		# Color health bar based on health percentage
		var health_pct = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		var health_color = Color.GREEN
		if health_pct < 0.3:
			health_color = Color.RED
		elif health_pct < 0.6:
			health_color = Color.YELLOW
		
		# Update health bar color (if possible)
		health_bar.modulate = health_color
	
	# Update card opacity if dead
	if not combatant_data.is_alive():
		card.modulate = Color(1, 1, 1, 0.5)  # Make it semi-transparent

func _update_combatant_status(combatant_name: String, status: String):
	"""Update a combatant's status text"""
	var card = null
	
	# Find the card
	if combatant_name in player_cards:
		card = player_cards[combatant_name]
	elif combatant_name in enemy_cards:
		card = enemy_cards[combatant_name]
	
	if not card:
		return
	
	var status_label = card.find_child("StatusLabel", true, false)
	if status_label:
		status_label.text = status.capitalize()
		
		# Color code the status
		if "attacking" in status.to_lower():
			status_label.add_theme_color_override("font_color", Color.RED)
		elif "defending" in status.to_lower():
			status_label.add_theme_color_override("font_color", Color.BLUE)
		elif "observing" in status.to_lower():
			status_label.add_theme_color_override("font_color", Color.YELLOW)
		elif "deciding" in status.to_lower():
			status_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			status_label.add_theme_color_override("font_color", Color.CYAN)

func _log_battle(message: String):
	"""Add message to battle log with better formatting"""
	if log_text:
		if log_text.text != "":
			log_text.text += "\n"
		log_text.text += message
		
		# Auto-scroll to bottom
		await get_tree().process_frame
		if log_text.get_v_scroll_bar():
			log_text.get_v_scroll_bar().value = log_text.get_v_scroll_bar().max_value

func show_battle():
	"""Show the battle window"""
	popup_centered()
	print("Battle window shown")
