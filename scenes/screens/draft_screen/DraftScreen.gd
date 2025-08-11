extends Control

# ── Types / systems ──────────────────────────────────────────────────────────
const AdventurerResource = preload("res://resources/Adventurer.gd")
const RoleResource       = preload("res://resources/Role.gd")
const DraftSystem        = preload("res://scripts/systems/draft_system.gd")

# ── Scene refs (your explicit paths) ─────────────────────────────────────────
@onready var lbl_clock: Label          = $Margin/Column/Header/OnClock
@onready var lbl_picks: Label          = $Margin/Column/Header/PicksRemaining
@onready var finish_btn: Button        = $Margin/Column/Footer/FinishBtn
@onready var ai_timer: Timer           = $AIPickTimer
@onready var scroll: ScrollContainer   = $Margin/Column/BodyPanel/BodyVBox/ProspectScroll
@onready var list_pad: MarginContainer = $Margin/Column/BodyPanel/BodyVBox/ProspectScroll/ListPad
@onready var list_box: VBoxContainer   = $Margin/Column/BodyPanel/BodyVBox/ProspectScroll/ListPad/ProspectList

# ── Data / state ─────────────────────────────────────────────────────────────
const ROLE_FILES := [
	"res://data/roles/navigator_role.tres",
	"res://data/roles/healer_role.tres",
	"res://data/roles/tank_role.tres",
	"res://data/roles/damage_role.tres",
]
const PLAYER_TEAM := 0
const TEAM_NAMES: Array[String] = ["You", "AI"]

var Draft                         # DraftSystem
var state                         # DraftState
var roles: Array[RoleResource] = []
var _busy: bool = false           # re-entrancy guard

# ── Fixed column widths (px) ─────────────────────────────────────────────────
const W_NAME     := 220
const W_ROLE     := 120
const W_STAT     := 60      # ATK / DEF / HP
const W_ROLESTAT := 180
const W_WAGE     := 80
const W_BTN      := 96

const ROW_H    := 36
const HEADER_H := 28
const SEP_X    := 8

# ── Debug helpers ────────────────────────────────────────────────────────────
func _log(msg: String) -> void:
	print("[DraftScreen] ", msg)

func _log_state(prefix := "") -> void:
	var pros := -1
	if state != null and state.prospects != null:
		pros = state.prospects.size()

	var pi := -1
	if state != null:
		pi = state.pick_index

	var done := false
	if state != null and Draft != null:
		done = Draft.is_done(state)

	_log("%s pros=%s pick_index=%s done=%s" % [prefix, str(pros), str(pi), str(done)])


# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	_log("ready()")
	if !_resolve_nodes():
		push_error("ProspectScroll/ListPad/ProspectList not found.")
		return

	randomize()
	roles = _load_roles()
	_log("roles loaded: %d" % roles.size())
	if roles.is_empty():
		push_error("No roles found in res://data/roles/. Create role .tres files.")
		return

	Draft = DraftSystem.new()
	var prospects: Array = _generate_prospects(6) # pool size
	_log("generated prospects: %d" % prospects.size())
	state = Draft.create_draft_state(prospects, TEAM_NAMES, 3, false)
	_log_state("after create_draft_state")

	finish_btn.disabled = true
	finish_btn.pressed.connect(_on_finish_pressed)

	ai_timer.one_shot = true
	ai_timer.autostart = false
	ai_timer.timeout.connect(_on_ai_timer_timeout)

	#_sync_list_width()
	#scroll.resized.connect(_sync_list_width)
	#resized.connect(_sync_list_width)

	_refresh()

func _resolve_nodes() -> bool:
	return scroll != null and list_pad != null and list_box != null

# ── Row helpers ──────────────────────────────────────────────────────────────
func _row_fixed(height := ROW_H, sep := SEP_X) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = height
	row.add_theme_constant_override("separation", sep)
	return row

func _header_label(text: String, w: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = w
	l.size_flags_horizontal = 0
	l.horizontal_alignment = align
	l.add_theme_color_override("font_color", Color(1,1,1,0.9))
	return l

func _cell_label(text: String, w: int, align := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = w
	l.size_flags_horizontal = 0
	l.horizontal_alignment = align
	return l

func _center_cell(node: Control, width: int) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.custom_minimum_size.x = width
	cc.add_child(node)
	return cc

func _flex_spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s

func _zebra_overlay(alpha: float) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(1,1,1,alpha)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.layout_mode = 1
	bg.anchors_preset = Control.PRESET_FULL_RECT
	return bg

# ── Builders ────────────────────────────────────────────────────────────────
func _make_header_row() -> HBoxContainer:
	var header := _row_fixed(HEADER_H, SEP_X)
	header.add_child(_header_label("Name",      W_NAME, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_header_label("Role",      W_ROLE))
	header.add_child(_header_label("ATK",       W_STAT))
	header.add_child(_header_label("DEF",       W_STAT))
	header.add_child(_header_label("HP",        W_STAT))
	header.add_child(_header_label("Role Stat", W_ROLESTAT, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_header_label("Wage",      W_WAGE))
	header.add_child(_flex_spacer())
	var lbl_action := _header_label("Action", 0, HORIZONTAL_ALIGNMENT_CENTER)
	header.add_child(_center_cell(lbl_action, W_BTN))
	var bg := _zebra_overlay(0.05)
	header.add_child(bg)
	header.move_child(bg, 0)
	return header

func _make_row(a: AdventurerResource, idx: int, player_turn: bool) -> HBoxContainer:
	var row := _row_fixed()

	var role_name := a.role.display_name if a.role else "—"
	var role_stat_label := str(a.role.role_stat_name) if a.role else "stat"

	row.add_child(_cell_label(a.name,                           W_NAME, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_cell_label(role_name,                        W_ROLE))
	row.add_child(_cell_label(str(a.attack),                    W_STAT))
	row.add_child(_cell_label(str(a.defense),                   W_STAT))
	row.add_child(_cell_label(str(a.hp),                        W_STAT))
	row.add_child(_cell_label("%s %d" % [role_stat_label, a.role_stat], W_ROLESTAT, HORIZONTAL_ALIGNMENT_LEFT))
	row.add_child(_cell_label("%dg" % a.wage,                   W_WAGE))
	row.add_child(_flex_spacer())

	var pick_idx := idx  # stable for this row
	var btn := Button.new()
	btn.text = "Pick"
	btn.custom_minimum_size = Vector2(80, 32)
	btn.disabled = !player_turn
	btn.pressed.connect(func():
		_log("btn pressed row=%d" % pick_idx)
		if _busy: _log("ignored: busy"); return
		if Draft == null or state == null: _log("ignored: null Draft/state"); return
		if Draft.is_done(state): _log("ignored: draft done"); return
		if !Draft.is_player_turn(state, PLAYER_TEAM): _log("ignored: not player turn"); return
		if state.prospects == null: _log("ignored: prospects null"); return
		if pick_idx < 0 or pick_idx >= state.prospects.size():
			_log("ignored: stale idx=%d size=%d" % [pick_idx, state.prospects.size()])
			return

		_busy = true
		btn.disabled = true
		if !ai_timer.is_stopped(): ai_timer.stop()

		_log("PICK start idx=%d" % pick_idx)
		_log_state("pre Draft.pick")
		Draft.pick(state, pick_idx)
		_log_state("post Draft.pick")

		call_deferred("_after_pick_safe")
	)
	row.add_child(_center_cell(btn, W_BTN))

	var zebra_alpha: float = 0.03 if (idx % 2 == 1) else 0.0
	var bg := _zebra_overlay(zebra_alpha)
	row.add_child(bg)
	row.move_child(bg, 0)
	return row

# ── Refresh / flow ──────────────────────────────────────────────────────────
func _refresh() -> void:
	_log("refresh() begin")
	_log_state("before build")

	finish_btn.disabled = !Draft.is_done(state)

	var team_i: int = Draft.current_team_index(state) if !Draft.is_done(state) else -1
	lbl_clock.text = ("On the clock: %s" % state.teams[team_i]["name"]) if team_i >= 0 else "Draft complete"
	lbl_picks.text = "Your picks left: %d" % _picks_left_for(PLAYER_TEAM)

	for c in list_box.get_children():
		c.queue_free()

	list_box.add_child(_make_header_row())

	var is_player_turn: bool = !Draft.is_done(state) and Draft.is_player_turn(state, PLAYER_TEAM)
	for i in state.prospects.size():
		list_box.add_child(_make_row(state.prospects[i], i, is_player_turn))

	# drive AI after a short delay, only when not busy
	# in _refresh(), replace the AI block with:
	if !_busy and !Draft.is_done(state) and !Draft.is_player_turn(state, PLAYER_TEAM):
		if ai_timer.is_stopped():
			_log("AI timer start (0.35s)")
			ai_timer.start(0.35) # one shot
		else:
			_log("AI timer already running")
	

	_log("refresh() end")

func _after_pick_safe() -> void:
	_log("_after_pick_safe() yield one frame")
	await get_tree().process_frame
	_after_pick()

func _after_pick() -> void:
	_log("_after_pick()")
	if Draft.is_done(state):
		finish_btn.disabled = false
	_refresh()
	_busy = false

# ── Buttons / AI ─────────────────────────────────────────────────────────────
func _on_finish_pressed() -> void:
	if Draft == null or state == null:
		push_warning("[DraftScreen] finish: no state")
		return

	var picked: Array = state.teams[PLAYER_TEAM]["roster"]
	print("[DraftScreen] finish: committing %d picks to Game.roster" % picked.size())

	# Append only new refs (avoid dupes if player re-enters)
	for a in picked:
		if !Game.roster.has(a):
			Game.roster.append(a)

	print("[DraftScreen] Game.roster size after commit: %d" % Game.roster.size())

	Game.goto(Game.Phase.GUILD)
	get_tree().change_scene_to_file("res://scenes/screens/guild_screen/guild_screen.tscn")


func _on_ai_timer_timeout() -> void:
	_log("_on_ai_timer_timeout")
	if _busy: _log("AI skipped: busy"); return
	if Draft.is_done(state): _log("AI skipped: done"); return
	if Draft.is_player_turn(state, PLAYER_TEAM): _log("AI skipped: player turn"); return

	var ai_team: int = Draft.current_team_index(state)
	_log("AI current team index = %d" % ai_team)
	var idx: int = Draft.ai_choose_index(state, ai_team)
	_log("AI chose idx=%d (pros size=%d)" % [idx, state.prospects.size()])

	if idx < 0 or idx >= state.prospects.size():
		_log("AI pick invalid; scheduling retry")
		# retry quickly in case the pool changed this frame
		ai_timer.start(0.2)
		return

	_busy = true
	_log("AI PICK idx=%d" % idx)
	_log_state("pre AI Draft.pick")
	Draft.pick(state, idx)
	_log_state("post AI Draft.pick")
	call_deferred("_after_pick_safe")


# ── Helpers ─────────────────────────────────────────────────────────────────
func _picks_left_for(team_i: int) -> int:
	var total_for_team := 0
	for t in state.order:
		if t == team_i: total_for_team += 1
	var made := 0
	for pi in range(0, min(state.pick_index, state.order.size())):
		if state.order[pi] == team_i: made += 1
	return max(0, total_for_team - made)

func _load_roles() -> Array[RoleResource]:
	var arr: Array[RoleResource] = []
	for path in ROLE_FILES:
		var r := load(path) as RoleResource
		if r == null: push_warning("Failed to load role at " + path)
		else: arr.append(r)
	return arr

func _generate_prospects(n: int) -> Array:
	_log("_generate_prospects n=%d roles=%d" % [n, roles.size()])
	var out: Array = []
	if roles.is_empty():
		push_error("No roles loaded, cannot generate prospects.")
		return out
	for i in n:
		var role: RoleResource = roles.pick_random()
		var a: AdventurerResource = AdventurerResource.new()
		a.role = role
		if a.has_method("apply_role_defaults"): a.apply_role_defaults()
		a.attack    += randi_range(-1, 1)
		a.defense   += randi_range(-1, 1)
		a.hp        += randi_range(-2, 2)
		a.role_stat += randi_range(0, 2)
		a.name = _random_name()
		a.wage = _calc_wage(a)
		out.append(a)
	return out

func _calc_wage(a) -> int:
	var base: float = 4.0
	var power: float = (a.attack * 1.0) + (a.defense * 0.7) + (a.hp * 0.15) + (a.role_stat * 0.5)
	return clampi(int(round(base + power / 8.0)), 3, 12)

func _random_name() -> String:
	var first = ["Garruk","Eryndra","Milo","Serah","Tamsin","Borin","Nyx","Quinn","Lira"]
	var last  = ["Stonefist","Dawnstar","Reed","Voss","Kestrel","Blackwood","Ashen","Thorne","Vale"]
	return "%s %s" % [first.pick_random(), last.pick_random()]

func _sync_list_width() -> void:
	if scroll == null or list_pad == null or list_box == null:
		_log("sync aborted: missing node(s)")
		return
	var ml := list_pad.get_theme_constant("margin_left", "MarginContainer")
	var mr := list_pad.get_theme_constant("margin_right", "MarginContainer")
	list_box.custom_minimum_size.x = max(0.0, scroll.size.x - float(ml + mr))
	_log("sync width set: %s" % str(list_box.custom_minimum_size.x))

func _process(_dt: float) -> void:
	if Draft == null or state == null: return
	if _busy: return
	if Draft.is_done(state): return
	if Draft.is_player_turn(state, PLAYER_TEAM): return
	# AI turn: ensure the timer is running
	if ai_timer.is_stopped():
		_log("AI watchdog starting timer")
		ai_timer.start(0.35)
