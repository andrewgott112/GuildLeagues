extends Control

@onready var season_label: Label = $Margin/Column/TopBar/SeasonLabel
@onready var lbl_gold: Label    = $Margin/Column/TopBar/GoldBox/GoldValue
@onready var roster_list: VBoxContainer = $Margin/Column/RosterPanel/RosterPanelVBox/RosterScroll/RosterList

@onready var btn_to_draft: Button = $Margin/Column/BottomBar/ToDraft
@onready var btn_save: Button     = $Margin/Column/BottomBar/SaveBtn
@onready var btn_menu: Button     = $Margin/Column/BottomBar/ToMenu


func _ready() -> void:
	_wire_buttons()
	_refresh_header()
	_populate_roster()

func _wire_buttons() -> void:
	btn_to_draft.pressed.connect(_on_to_draft)
	btn_save.pressed.connect(_on_save_pressed)
	btn_menu.pressed.connect(_on_main_menu)

func _refresh_header() -> void:
	season_label.text = "Season %d" % Game.season
	lbl_gold.text = str(Game.gold)

func _populate_roster() -> void:
	# Clear old rows
	for c in roster_list.get_children():
		c.queue_free()

	if Game.roster.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No adventurers yet. Head to the draft!"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		roster_list.add_child(empty_label)
		return

	# Create a simple header row
	roster_list.add_child(_make_header_row())

	# One row per adventurer
	for adv in Game.roster:
		roster_list.add_child(_make_roster_row(adv))

func _make_header_row() -> Control:
	var row := HBoxContainer.new()
	row.add_child(_col_label("Name", true))
	row.add_child(_col_label("Role", true))
	row.add_child(_col_label("ATK", true))
	row.add_child(_col_label("DEF", true))
	row.add_child(_col_label("HP", true))
	row.add_child(_col_label("Role Stat", true))
	row.add_child(_col_label("Wage", true))
	return row

func _make_roster_row(adv: Resource) -> Control:
	var row := HBoxContainer.new()
	row.add_child(_col_label(adv.name))
	row.add_child(_col_label(adv.role.display_name if adv.role else "—"))
	row.add_child(_col_label(str(adv.attack)))
	row.add_child(_col_label(str(adv.defense)))
	row.add_child(_col_label(str(adv.hp)))

	var role_stat_name: StringName
	if adv.role:
		role_stat_name = adv.role.role_stat_name
	else:
		role_stat_name = &"stat"

	row.add_child(_col_label("%s: %s" % [str(role_stat_name), str(adv.role_stat)]))
	row.add_child(_col_label("%dg" % adv.wage))
	return row


func _col_label(text: String, is_header := false) -> Label:
	var l := Label.new()
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if is_header:
		l.add_theme_color_override("font_color", Color(1,1,1))
		l.add_theme_constant_override("outline_size", 1)
	return l

func _on_to_draft() -> void:
	Game.goto(Game.Phase.DRAFT)
	_switch_scene("res://scenes/screens/draft/DraftScreen.tscn")

func _on_save_pressed() -> void:
	# Hook your Save autoload later
	print("Save not implemented yet.")

func _on_main_menu() -> void:
	Game.goto(Game.Phase.MAIN_MENU)
	_switch_scene("res://scenes/screens/main_menu/main_menu.tscn")

func _switch_scene(path: String) -> void:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_error("Scene not found or not a PackedScene: " + path)
		return

	var inst: Node = packed.instantiate()
	get_tree().root.add_child(inst)
	queue_free()
