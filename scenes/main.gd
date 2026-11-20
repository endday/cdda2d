extends Node2D
## CDDA2D 适配层：2D 俯视、FOV、HUD、输入、物品栏。
## 规则在 World + Action + ItemUse；这里只画和翻译输入。
## 贴图来自 CDDA 的 UltiCa tileset（CC BY-SA 3.0，见 content/tiles/CREDITS.md）。

const CELL := 32
const ACTOR_H := 48
const W := World.W
const H := World.H
## 等距投影：2:1 菱形地砖。一格在屏幕上占 64×32，往上就是墙的高度。
const ISO_W := 64
const ISO_H := 32
const WALL_H := 40
const DOOR_H := 28
const ACTOR_SCALE := 1.5
const ZOOM := 1.1
const MOVE_SMOOTH := 16.0    # 越大越跟手；16 ≈ 0.15 秒走完一格

var world: World
var camera: Camera2D
var ui_layer: CanvasLayer
var ui_root: Control
var labels: Dictionary = {}
var bars: Dictionary = {}
var survivor_panel: Panel
var raid_panel: Panel
var log_panel: Panel
var log_label: Label
var status_label: Label
var hint_label: Label
var attribution_label: Label
var raid_label: Label
var load_label: Label
var threat_label: Label
var interaction_label: Label
var auto_supply_toggle: CheckButton
var deployment_auto_supply_toggle: CheckButton
var bottom_panel: Panel
var action_buttons: Array[Button] = []
var equipment_panel: Panel
var equipment_slots: Dictionary = {}
var inventory_overlay: ColorRect
var inventory_close_button: Button
var deployment_overlay: ColorRect
var deployment_panel: Panel
var deployment_scroll: ScrollContainer
var deployment_list: VBoxContainer
var deployment_info: Label
var deployment_open := false
var selected_stash_indices: Array[int] = []

var inv_panel: Panel
var inv_label: Label
var inventory_open := false
var item_action_open := false
var item_action_item: Item = null
var item_action_options: Array = []
var item_context_panel: Panel
var item_context_list: VBoxContainer
var inventory_scroll: ScrollContainer
var inventory_list: GridContainer

var tile_texture: Texture2D
var actor_texture: Texture2D
var tiles_meta: Dictionary = {}
var ui_font: FontFile

var iso_texture: Texture2D
var iso_cells: Dictionary = {}   # 名字 -> 图集里的序号
const ISO_NAMES := ["floor", "pavement", "wall", "rock", "door_closed", "door_open"]

## 每个 Actor 的屏幕位置（世界像素），用来把一格一格的跳变抹成滑动。
var _visual: Dictionary = {}
var _move_cooldown := 0.0     # 按住方向键时限制节奏，别让动画追不上

var item_data: Dictionary = {}
var monster_data: Dictionary = {}
var profile_stash: Array[String] = []
var profile_outcome_saved := false
var mouse_destination := Vector2i(-999, -999)
var mouse_destination_position := Vector2.ZERO
var mouse_move_timer := 0.0
var hover_cell := Vector2i(-999, -999)
var mouse_search_container := false
const MOUSE_MOVE_INTERVAL := 0.09

## 整体压一点冷色，别让 UltiCa 的木地板太橘。
const TINT := Color(0.82, 0.85, 0.9)


func _ready() -> void:
	var items := _load_json_array("res://content/items.json")
	var monsters := _load_json_array("res://content/monsters.json")
	_validate_content(items, monsters)
	item_data = ContentDB.index_by_id(items)
	monster_data = ContentDB.index_by_id(monsters)
	world = World.new(item_data, monster_data)
	_load_profile()
	_load_tiles()
	_load_font()
	_build_camera()
	_build_ui()
	_open_deployment_screen()
	_refresh_ui()
	queue_redraw()


func _load_json_array(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("%s 读不到" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_ARRAY:
		push_error("%s 不是数组" % path)
		return []
	return parsed


func _load_profile() -> void:
	profile_stash.clear()
	var file := FileAccess.open("user://profile.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for entry: Variant in (parsed as Dictionary).get("stash", []):
		var item_id := String(entry)
		if item_data.has(item_id):
			profile_stash.append(item_id)
	if (parsed as Dictionary).has("auto_supply_enabled"):
		world.auto_supply_enabled = bool((parsed as Dictionary)["auto_supply_enabled"])


func _save_profile() -> void:
	var file := FileAccess.open("user://profile.json", FileAccess.WRITE)
	if file == null:
		world.log_message("仓库存档失败。")
		return
	file.store_string(JSON.stringify({
		"stash": profile_stash,
		"auto_supply_enabled": world.auto_supply_enabled,
	}))


## 内容有问题就别猜，直接报到日志里，方便测试和 CI 抓。
func _validate_content(items: Array, monsters: Array) -> void:
	var problems: Array[String] = []
	problems.append_array(ContentDB.validate_items(items))
	problems.append_array(ContentDB.validate_monsters(monsters))
	problems.append_array(ContentDB.validate_disassemble_references(items, ContentDB.index_by_id(items)))
	problems.append_array(
		ContentDB.validate_references(World.SPAWN_ITEMS, ContentDB.index_by_id(items), "地面物品"))
	for problem: String in problems:
		push_error("[content] %s" % problem)


func _load_tiles() -> void:
	var file := FileAccess.open("res://content/tiles/tiles.json", FileAccess.READ)
	if file == null:
		push_error("content/tiles/tiles.json 读不到，只能退回纯色")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("content/tiles/tiles.json 不是对象")
		return
	tiles_meta = parsed
	tile_texture = load("res://content/tiles/" + String(parsed.get("tileset", "tileset.png")))
	var actors: Dictionary = parsed.get("actors", {})
	actor_texture = load("res://content/tiles/" + String(actors.get("image", "actors.png")))
	_load_iso()


## 等距贴图（tools/build_iso.py 生成）。没有就退回纯色菱形。
func _load_iso() -> void:
	var file := FileAccess.open("res://content/tiles/iso.json", FileAccess.READ)
	if file == null:
		push_error("content/tiles/iso.json 读不到，跑一下 tools/build_iso.py")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	iso_texture = load("res://content/tiles/" + String(parsed.get("image", "iso.png")))
	iso_cells = parsed.get("tiles", {})


## Web 端没有系统字体兜底，必须自带一份中文字体子集（tools/build_font.py）。
func _load_font() -> void:
	var resource: Resource = load("res://content/fonts/ui.otf")
	if resource is FontFile:
		ui_font = resource
	else:
		push_error("content/fonts/ui.otf 读不到，中文会变方块")


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.position = _actor_world_pos(world.player) + Vector2(0, ISO_H / 2.0)
	camera.zoom = Vector2(ZOOM, ZOOM)
	add_child(camera)


# ================================================================ HUD

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	ui_layer = layer
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	survivor_panel = _panel(ui_root, Rect2(18, 18, 340, 208))
	var panel_title := _label(survivor_panel, "幸存者  /  行动 01", Vector2(14, -1), 11, Color("#76908c"))
	panel_title.position.y = -18
	labels["hp"] = _label(survivor_panel, "", Vector2(14, 10), 15, Color("#e8f1ea"))
	bars["hp"] = _bar(survivor_panel, Vector2(14, 34), Vector2(272, 10), Color("#c0504d"))
	labels["needs"] = _label(survivor_panel, "", Vector2(14, 52), 13, Color("#c8d6c0"))
	bars["hunger"] = _bar(survivor_panel, Vector2(14, 76), Vector2(132, 8), Color("#c9a15a"))
	bars["thirst"] = _bar(survivor_panel, Vector2(154, 76), Vector2(132, 8), Color("#5a9fc9"))
	labels["stamina"] = _label(survivor_panel, "", Vector2(14, 90), 11, Color("#d9b27b"))
	bars["stamina"] = _bar(survivor_panel, Vector2(14, 108), Vector2(312, 8), Color("#d69b5a"))
	labels["ap"] = _label(survivor_panel, "", Vector2(14, 124), 12, Color("#9fd4c4"))
	labels["turn"] = _label(survivor_panel, "", Vector2(14, 148), 12, Color("#7d9188"))
	auto_supply_toggle = _new_check_button()
	auto_supply_toggle.text = "自动补给"
	auto_supply_toggle.position = Vector2(8, 174)
	auto_supply_toggle.size = Vector2(190, 26)
	auto_supply_toggle.button_pressed = world.auto_supply_enabled
	auto_supply_toggle.tooltip_text = "需求低于 25% 且附近没有可见敌人时，自动使用普通食物或水，每件消耗 50 行动点。"
	auto_supply_toggle.add_theme_font_size_override("font_size", 11)
	auto_supply_toggle.add_theme_color_override("font_color", Color("#c3d0b9"))
	auto_supply_toggle.toggled.connect(_on_auto_supply_toggled)
	survivor_panel.add_child(auto_supply_toggle)

	raid_panel = _panel(ui_root, Rect2(930, 18, 332, 194))
	_label(raid_panel, "行动状态", Vector2(16, 12), 11, Color("#76908c"))
	raid_label = _label(raid_panel, "", Vector2(16, 34), 15, Color("#eecb80"))
	threat_label = _label(raid_panel, "", Vector2(16, 64), 13, Color("#c3d0b9"))
	load_label = _label(raid_panel, "", Vector2(16, 92), 12, Color("#9fd4c4"))
	load_label.size = Vector2(300, 42)
	_label(raid_panel, "操作提示", Vector2(16, 146), 11, Color("#76908c"))
	_label(raid_panel, "左键移动/目标   右键查看   I 背包", Vector2(16, 164), 11, Color("#c3d0b9"))

	log_panel = _panel(ui_root, Rect2(18, 552, 620, 112))
	log_label = _label(log_panel, "", Vector2(14, 8), 13, Color("#c3d0b9"))
	log_label.size = Vector2(592, 92)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	status_label = _label(ui_root, "", Vector2(382, 28), 15, Color("#eecb80"))
	status_label.size = Vector2(520, 54)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	interaction_label = _label(ui_root, "", Vector2(382, 88), 13, Color("#c3d0b9"))
	interaction_label.size = Vector2(500, 44)
	interaction_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label = _label(ui_root,
		"WASD/方向键/hjkl 走，yubn 斜走   ' / \" 跑步   i 背包   , 搜   e 交互   . 等   F5 存 F9 读 R 重开",
		Vector2(18, 682), 11, Color("#7d9188"))
	# CC BY-SA 要求署名：把这行留在画面里，别只写在 README。
	attribution_label = _label(ui_root, "Tiles: Cataclysm DDA UltiCa, CC BY-SA 3.0",
		Vector2(940, 704), 11, Color("#7d9188"))
	attribution_label.size = Vector2(322, 18)
	attribution_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	bottom_panel = _panel(ui_root, Rect2(662, 552, 600, 112))
	_build_action_buttons(bottom_panel)

	inventory_overlay = ColorRect.new()
	inventory_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inventory_overlay.color = Color(0.01, 0.018, 0.026, 0.88)
	inventory_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	inventory_overlay.visible = false
	ui_root.add_child(inventory_overlay)

	inv_panel = _panel(ui_root, Rect2(64, 42, 1152, 636))
	inv_panel.visible = false
	var inventory_header := _label(inv_panel, "物品栏  /  装备", Vector2(24, 18), 18, Color("#e7f4ef"))
	var inventory_subtitle := _label(inv_panel, "本次行动  ·  携带物品与装备", Vector2(26, 47), 11, Color("#7fa99d"))
	var divider := ColorRect.new()
	divider.position = Vector2(24, 70)
	divider.size = Vector2(1104, 1)
	divider.color = Color("#29464c")
	inv_panel.add_child(divider)
	inv_label = _label(inv_panel, "", Vector2(24, 86), 13, Color("#c3d0b9"))
	inv_label.size = Vector2(510, 52)
	inventory_scroll = ScrollContainer.new()
	inventory_scroll.position = Vector2(24, 148)
	inventory_scroll.size = Vector2(510, 484)
	inventory_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_panel.add_child(inventory_scroll)
	inventory_list = GridContainer.new()
	inventory_list.columns = 2
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_list.custom_minimum_size.x = 510
	inventory_list.add_theme_constant_override("separation", 6)
	inventory_scroll.add_child(inventory_list)
	_build_equipment_panel(inv_panel)
	inventory_close_button = _new_button()
	inventory_close_button.text = "ESC  关闭"
	inventory_close_button.position = Vector2(1018, 18)
	inventory_close_button.size = Vector2(110, 34)
	inventory_close_button.add_theme_font_size_override("font_size", 11)
	inventory_close_button.add_theme_color_override("font_color", Color("#c3d0b9"))
	inventory_close_button.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#31454a")))
	inventory_close_button.add_theme_stylebox_override("hover", _button_style(Color("#3a2028"), Color("#d47b7b")))
	inventory_close_button.pressed.connect(_close_inventory)
	inv_panel.add_child(inventory_close_button)
	_build_deployment_screen(ui_root)
	item_context_panel = _panel(ui_root, Rect2(Vector2.ZERO, Vector2.ZERO))
	item_context_panel.visible = false
	item_context_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	item_context_list = VBoxContainer.new()
	item_context_list.position = Vector2(6, 6)
	item_context_list.add_theme_constant_override("separation", 3)
	item_context_panel.add_child(item_context_list)
	ui_root.resized.connect(_layout_ui)
	get_window().size_changed.connect(_layout_ui)
	_layout_ui()


func _layout_ui() -> void:
	if ui_root == null or survivor_panel == null or raid_panel == null:
		return
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var width := viewport_size.x
	var height := viewport_size.y
	var compact_layout := get_window().size.x < 1100
	var margin := 18.0
	var horizontal_scale := (width - margin * 3.0) / 672.0
	var vertical_scale := (height - 282.0) / 286.0
	var top_scale := clampf(minf(horizontal_scale, vertical_scale), 0.35, 1.0)
	survivor_panel.scale = Vector2.ONE * top_scale
	raid_panel.scale = Vector2.ONE * top_scale
	survivor_panel.position = Vector2(margin, margin)
	raid_panel.position = Vector2(width - margin - 332.0 * top_scale, margin)

	if not compact_layout:
		raid_panel.size.y = 194.0
		status_label.scale = Vector2.ONE
		interaction_label.scale = Vector2.ONE
		status_label.position = Vector2(382.0, 28.0)
		status_label.size = Vector2(maxf(250.0, raid_panel.position.x - 406.0), 54.0)
		interaction_label.position = Vector2(382.0, 88.0)
		interaction_label.size = Vector2(maxf(250.0, raid_panel.position.x - 406.0), 44.0)
	else:
		raid_panel.size.y = 286.0
		status_label.scale = Vector2.ONE * top_scale
		interaction_label.scale = Vector2.ONE * top_scale
		status_label.position = raid_panel.position + Vector2(16.0, 198.0) * top_scale
		status_label.size = Vector2(300.0, 38.0)
		interaction_label.position = raid_panel.position + Vector2(16.0, 232.0) * top_scale
		interaction_label.size = Vector2(300.0, 42.0)

	var bottom_y := height - 168.0
	if not compact_layout:
		var column_width := (width - margin * 2.0 - 24.0) * 0.5
		log_panel.position = Vector2(margin, bottom_y)
		log_panel.size = Vector2(column_width, 112.0)
		bottom_panel.position = Vector2(margin + column_width + 24.0, bottom_y)
		bottom_panel.size = Vector2(column_width, 112.0)
		log_label.size = Vector2(column_width - 28.0, 96.0)
	else:
		var full_width := width - margin * 2.0
		log_panel.position = Vector2(margin, bottom_y - 96.0)
		log_panel.size = Vector2(full_width, 84.0)
		bottom_panel.position = Vector2(margin, bottom_y)
		bottom_panel.size = Vector2(full_width, 112.0)
		log_label.size = Vector2(full_width - 28.0, 68.0)

	var button_gap := 8.0
	var button_width := (bottom_panel.size.x - 32.0 - button_gap * 4.0) / 5.0
	for index: int in action_buttons.size():
		action_buttons[index].position = Vector2(16.0 + index * (button_width + button_gap), 42.0)
		action_buttons[index].size = Vector2(button_width, 42.0)

	hint_label.position = Vector2(margin, height - 38.0)
	hint_label.size = Vector2(maxf(0.0, width - margin * 2.0), 18.0)
	if compact_layout:
		hint_label.text = "WASD 移动  鼠标寻路  I 背包  , 拾取  E 交互  . 等待  F5/F9 存读档"
	else:
		hint_label.text = "WASD/方向键/hjkl 走，yubn 斜走   ' / \" 跑步   i 背包   , 拾取   e 交互   . 等待   F5 存 F9 读 R 重开"
	if attribution_label != null:
		attribution_label.position = Vector2(maxf(margin, width - 340.0), height - 18.0)

	if inv_panel != null:
		var inventory_scale := clampf(minf((width - margin * 2.0) / 1152.0, (height - margin * 2.0) / 636.0), 0.3, 1.0)
		inv_panel.scale = Vector2.ONE * inventory_scale
		inv_panel.position = (viewport_size - Vector2(1152.0, 636.0) * inventory_scale) * 0.5
	if deployment_panel != null:
		var deployment_scale := clampf(minf((width - margin * 2.0) / 780.0, (height - margin * 2.0) / 556.0), 0.3, 1.0)
		deployment_panel.scale = Vector2.ONE * deployment_scale
		deployment_panel.position = (viewport_size - Vector2(780.0, 556.0) * deployment_scale) * 0.5


func _build_deployment_screen(parent: Control) -> void:
	deployment_overlay = ColorRect.new()
	deployment_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	deployment_overlay.color = Color(0.01, 0.018, 0.026, 0.9)
	deployment_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	deployment_overlay.visible = false
	parent.add_child(deployment_overlay)
	deployment_panel = _panel(parent, Rect2(250, 82, 780, 556))
	deployment_panel.visible = false
	_label(deployment_panel, "安全屋  /  整备", Vector2(28, 22), 20, Color("#e7f4ef"))
	_label(deployment_panel, "选择带入本局的仓库物资。未选中的物品留在基地。", Vector2(30, 58), 12, Color("#91aaa4"))
	deployment_info = _label(deployment_panel, "", Vector2(30, 92), 12, Color("#eecb80"))
	deployment_scroll = ScrollContainer.new()
	deployment_scroll.position = Vector2(30, 128)
	deployment_scroll.size = Vector2(720, 340)
	deployment_panel.add_child(deployment_scroll)
	deployment_list = VBoxContainer.new()
	deployment_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deployment_list.add_theme_constant_override("separation", 5)
	deployment_scroll.add_child(deployment_list)
	deployment_auto_supply_toggle = _new_check_button()
	deployment_auto_supply_toggle.text = "自动补给"
	deployment_auto_supply_toggle.position = Vector2(30, 496)
	deployment_auto_supply_toggle.size = Vector2(220, 32)
	deployment_auto_supply_toggle.button_pressed = world.auto_supply_enabled
	deployment_auto_supply_toggle.tooltip_text = "需求低于 25% 且附近没有可见敌人时自动使用普通补给。"
	deployment_auto_supply_toggle.add_theme_font_size_override("font_size", 12)
	deployment_auto_supply_toggle.add_theme_color_override("font_color", Color("#c3d0b9"))
	deployment_auto_supply_toggle.toggled.connect(_on_auto_supply_toggled)
	deployment_panel.add_child(deployment_auto_supply_toggle)
	var deploy_button := _new_button()
	deploy_button.text = "出发行动"
	deploy_button.position = Vector2(548, 486)
	deploy_button.size = Vector2(202, 46)
	deploy_button.add_theme_font_size_override("font_size", 14)
	deploy_button.add_theme_color_override("font_color", Color("#e7f4ef"))
	deploy_button.add_theme_stylebox_override("normal", _button_style(Color("#173c3c"), Color("#72b8a9")))
	deploy_button.add_theme_stylebox_override("hover", _button_style(Color("#20544f"), Color("#b2e6d5")))
	deploy_button.pressed.connect(_deploy_raid)
	deployment_panel.add_child(deploy_button)


func _open_deployment_screen() -> void:
	deployment_open = true
	selected_stash_indices.clear()
	for i: int in range(mini(3, profile_stash.size())):
		selected_stash_indices.append(i)
	_rebuild_deployment_list()
	_refresh_ui()


func _on_auto_supply_toggled(enabled: bool) -> void:
	world.auto_supply_enabled = enabled
	_save_profile()
	world.log_message("自动补给已开启。" if enabled else "自动补给已关闭。")
	refresh_ui()


func _rebuild_deployment_list() -> void:
	for child: Node in deployment_list.get_children():
		child.free()
	if profile_stash.is_empty():
		_add_starter_kit_card("主手武器", "小刀", "0.4 kg  ·  6 近战伤害")
		_add_starter_kit_card("饮水", "瓶装水", "0.5 kg  ·  恢复 40 水分")
		_add_starter_kit_card("食物", "罐头", "0.4 kg  ·  恢复 35 饱腹")
		_add_starter_kit_card("医疗", "绷带", "0.1 kg  ·  恢复生命")
		_add_starter_kit_card("背负", "背包", "1.0 kg  ·  增加 20 L 容积")
		deployment_info.text = "基础口袋 6 L，背包装备后共 26 L。成功撤离可将物资存入仓库。"
		return
	for i: int in profile_stash.size():
		var item_id: String = profile_stash[i]
		var prototype: Dictionary = item_data.get(item_id, {})
		var check := _new_check_button()
		check.text = "%s    %.1f kg   %.1f L" % [
			String(prototype.get("name", item_id)),
			float(prototype.get("weight", 0.0)),
			float(prototype.get("volume", 0)) / 1000.0,
		]
		check.button_pressed = selected_stash_indices.has(i)
		check.custom_minimum_size = Vector2(710, 38)
		check.add_theme_font_size_override("font_size", 12)
		check.add_theme_color_override("font_color", Color("#c3d0b9"))
		check.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#283b40")))
		check.add_theme_stylebox_override("hover", _button_style(Color("#19343a"), Color("#83b6a7")))
		check.toggled.connect(_on_loadout_toggled.bind(i))
		deployment_list.add_child(check)
	_update_deployment_info()


func _add_starter_kit_card(category: String, item_name: String, detail: String) -> void:
	var card := _new_button()
	card.text = "%s     %s\n           %s" % [category, item_name, detail]
	card.custom_minimum_size = Vector2(700, 64)
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.disabled = true
	card.add_theme_font_size_override("font_size", 13)
	card.add_theme_color_override("font_color", Color("#c3d0b9"))
	card.add_theme_color_override("font_disabled_color", Color("#c3d0b9"))
	card.add_theme_stylebox_override("disabled", _button_style(Color("#101a1d"), Color("#31454a")))
	deployment_list.add_child(card)


func _on_loadout_toggled(enabled: bool, stash_index: int) -> void:
	if enabled and not selected_stash_indices.has(stash_index):
		selected_stash_indices.append(stash_index)
	elif not enabled:
		selected_stash_indices.erase(stash_index)
	_update_deployment_info()


func _update_deployment_info() -> void:
	var weight := 0.0
	var volume := 0
	var capacity := Actor.BASE_CAPACITY_VOLUME
	for index: int in selected_stash_indices:
		if index < 0 or index >= profile_stash.size():
			continue
		var prototype: Dictionary = item_data.get(profile_stash[index], {})
		weight += float(prototype.get("weight", 0.0))
		volume += int(prototype.get("volume", 0))
		capacity += int(prototype.get("capacity_volume", 0))
	var overloaded := weight > Actor.BASE_MAX_WEIGHT or volume > capacity
	deployment_info.text = "%s  已选 %d 件   %.1f / %.1f kg   %.1f / %.1f L   仓库 %d 件" % [
		"超出携带上限" if overloaded else "携带能力正常",
		selected_stash_indices.size(), weight, Actor.BASE_MAX_WEIGHT,
		float(volume) / 1000.0, float(capacity) / 1000.0, profile_stash.size(),
	]
	deployment_info.add_theme_color_override("font_color", Color("#e07070") if overloaded else Color("#eecb80"))


func _deploy_raid() -> void:
	var selected: Dictionary = {}
	for index: int in selected_stash_indices:
		selected[index] = true
	var remaining: Array[String] = []
	var selected_items: Array[Item] = []
	for i: int in profile_stash.size():
		var item_id: String = profile_stash[i]
		if selected.has(i):
			selected_items.append(Item.new(item_id))
		else:
			remaining.append(item_id)
	var loaded := 0
	var items_to_pack: Array[Item] = []
	for item: Item in selected_items:
		var prototype := item.prototype(item_data)
		var item_weight := float(prototype.get("weight", 0.0))
		if world.player.total_weight(item_data) + item_weight > world.player.max_weight:
			remaining.append(item.type_id)
			continue
		world.player.take_item(item)
		var equipped := false
		if prototype.has("melee") and world.player.wielded == null:
			equipped = world.player.wield_item(item)
		elif prototype.has("wear_slot") or prototype.has("armor") or prototype.has("capacity_volume"):
			equipped = world.player.wear_item(item, item_data)
		if equipped:
			loaded += 1
		else:
			world.player.remove_item(item)
			items_to_pack.append(item)
	for item: Item in items_to_pack:
		if world.player.carry_error(item, item_data).is_empty():
			world.player.take_item(item)
			loaded += 1
		else:
			remaining.append(item.type_id)
	profile_stash = remaining
	if loaded == 0:
		for item_id: String in ["knife", "water", "canned_food", "bandage", "backpack"]:
			var item := Item.new(item_id)
			if not item_data.has(item_id) or not world.player.carry_error(item, item_data).is_empty():
				continue
			world.player.take_item(item)
			var prototype := item.prototype(item_data)
			if prototype.has("melee") and world.player.wielded == null:
				world.player.wield_item(item)
			elif prototype.has("wear_slot") or prototype.has("armor") or prototype.has("capacity_volume"):
				world.player.wear_item(item, item_data)
	world.stash = profile_stash.duplicate()
	_save_profile()
	deployment_open = false
	profile_outcome_saved = false
	_refresh_ui()
	queue_redraw()


func _build_equipment_panel(parent: Panel) -> void:
	equipment_panel = _panel(parent, Rect2(560, 86, 568, 546))
	_label(equipment_panel, "装备状态", Vector2(20, 18), 15, Color("#e7f4ef"))
	_label(equipment_panel, "拖拽物品到槽位换装，右键打开动作菜单", Vector2(20, 46), 11, Color("#7d9188"))
	var figure := _label(equipment_panel, "             O\n           / | \\\n             |\n            / \\", Vector2(220, 94), 29, Color("#7fa99d"))
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	figure.size = Vector2(128, 188)
	_add_equipment_slot("head", "头部", Vector2(20, 94), Vector2(140, 58))
	_add_equipment_slot("main_hand", "主手", Vector2(20, 170), Vector2(140, 62))
	_add_equipment_slot("body", "身体", Vector2(408, 94), Vector2(140, 62))
	_add_equipment_slot("off_hand", "副手", Vector2(408, 170), Vector2(140, 62))
	_add_equipment_slot("backpack", "背包", Vector2(20, 268), Vector2(140, 62))
	_add_equipment_slot("legs", "腿部", Vector2(408, 268), Vector2(140, 62))
	_add_equipment_slot("feet", "脚部", Vector2(150, 368), Vector2(140, 62))
	_add_equipment_slot("quick", "快捷栏", Vector2(298, 368), Vector2(140, 62))
	_label(equipment_panel, "装备规则", Vector2(20, 466), 11, Color("#76908c"))
	_label(equipment_panel, "主手攻击优先，主手空时副手武器可攻击    穿戴不占背包容积", Vector2(20, 488), 11, Color("#c3d0b9"))


func _add_equipment_slot(slot_id: String, title: String, position: Vector2, size: Vector2) -> void:
	var button := _new_item_drag_button()
	button.name = "Equipment_" + slot_id
	button.text = title + "\n空"
	button.equipment_slot_id = slot_id
	button.position = position
	button.size = size
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_color_override("font_color", Color("#c3d0b9"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#283b40")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#19343a"), Color("#83b6a7")))
	button.pressed.connect(_on_equipment_slot_pressed.bind(slot_id))
	button.gui_input.connect(_on_equipment_slot_gui_input.bind(slot_id))
	button.item_dropped.connect(_on_inventory_item_dropped_on_slot)
	equipment_panel.add_child(button)
	equipment_slots[slot_id] = button


func _refresh_equipment_panel() -> void:
	if equipment_panel == null:
		return
	var p := world.player
	_set_equipment_slot("head", "头部", _worn_name("head"))
	_set_equipment_slot("main_hand", "主手", "空手" if p.wielded == null else world.item_name(p.wielded.type_id))
	_set_equipment_slot("body", "身体", _worn_name("body"))
	_set_equipment_slot("backpack", "背包", _worn_name("backpack"))
	_set_equipment_slot("off_hand", "副手", "空" if p.offhand == null else world.item_name(p.offhand.type_id))
	_set_equipment_slot("legs", "腿部", _worn_name("legs"))
	_set_equipment_slot("feet", "脚部", _worn_name("feet"))
	_set_equipment_slot("quick", "快捷栏", "未开放")


func _worn_name(slot: String) -> String:
	var item := world.player.worn_in_slot(slot, world.item_db)
	return "空" if item == null else world.item_name(item.type_id)


func _set_equipment_slot(slot_id: String, title: String, value: String) -> void:
	var button: Button = equipment_slots.get(slot_id)
	if button != null:
		button.text = "%s\n%s" % [title, value]


func _on_equipment_slot_pressed(slot_id: String) -> void:
	if slot_id == "quick":
		world.log_message("快捷栏还没有接入。")
		refresh_ui()
		return
	var item: Item = null
	if slot_id == "main_hand":
		item = world.player.wielded
		if item == null:
			for candidate: Item in world.player.inventory:
				if candidate.prototype(world.item_db).has("melee"):
					item = candidate
					break
	elif slot_id == "off_hand":
		item = world.player.offhand
		if item == null:
			for candidate: Item in world.player.inventory:
				if world.player.can_hold_offhand(candidate, world.item_db):
					item = candidate
					break
	else:
		item = world.player.worn_in_slot(slot_id, world.item_db)
		if item == null:
			for candidate: Item in world.player.inventory:
				if world.player.equipment_slot(candidate.prototype(world.item_db)) == slot_id:
					item = candidate
					break
	if item == null:
		world.log_message("背包里没有适合这个装备位的物品。")
		refresh_ui()
		return
	item_action_item = item
	item_action_options = ItemActions.available(item, world.player, world)
	item_action_open = not item_action_options.is_empty()
	refresh_ui()


func _build_action_buttons(parent: Panel) -> void:
	var entries := [
		{"id": "loot", "label": "拾取", "hotkey": ","},
		{"id": "examine", "label": "检查", "hotkey": "E"},
		{"id": "inventory", "label": "背包", "hotkey": "I"},
		{"id": "wait", "label": "等待", "hotkey": "."},
		{"id": "run", "label": "跑步", "hotkey": "'"},
	]
	var x := 16.0
	for entry: Dictionary in entries:
		var button := _new_button()
		button.text = "%s  %s" % [entry["hotkey"], entry["label"]]
		button.position = Vector2(x, 42)
		button.size = Vector2(104, 42)
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", Color("#d9e5dd"))
		button.add_theme_color_override("font_hover_color", Color("#ffffff"))
		button.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#31454a")))
		button.add_theme_stylebox_override("hover", _button_style(Color("#19343a"), Color("#83b6a7")))
		button.pressed.connect(_on_action_button.bind(String(entry["id"])))
		parent.add_child(button)
		action_buttons.append(button)
		x += 114.0


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style


func _panel(parent: Node, rect: Rect2) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.06, 0.92)
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _label(parent: Node, text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	_apply_ui_font(label)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _apply_ui_font(control: Control) -> void:
	if ui_font != null:
		control.add_theme_font_override("font", ui_font)


func _new_button() -> Button:
	var button := Button.new()
	_apply_ui_font(button)
	return button


func _new_check_button() -> CheckButton:
	var button := CheckButton.new()
	_apply_ui_font(button)
	return button


func _new_item_drag_button() -> ItemDragButton:
	var button := ItemDragButton.new()
	_apply_ui_font(button)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


func _bar(parent: Node, pos: Vector2, size: Vector2, color: Color) -> Dictionary:
	var back := ColorRect.new()
	back.position = pos
	back.size = size + Vector2(0, 2)
	back.color = Color(1, 1, 1, 0.08)
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.position = pos
	fill.size = size
	fill.color = color
	parent.add_child(fill)
	return {"back": back, "fill": fill, "width": size.x}


func _set_bar(name: String, value: int, maximum: int, color: Color) -> void:
	var bar: Dictionary = bars.get(name, {})
	if bar.is_empty():
		return
	var ratio: float = clampf(float(value) / float(maxi(1, maximum)), 0.0, 1.0)
	var fill: ColorRect = bar["fill"]
	fill.size = Vector2(float(bar["width"]) * ratio, fill.size.y)
	fill.color = color


func _refresh_ui() -> void:
	var p := world.player
	if auto_supply_toggle != null:
		auto_supply_toggle.set_pressed_no_signal(world.auto_supply_enabled)
	if deployment_auto_supply_toggle != null:
		deployment_auto_supply_toggle.set_pressed_no_signal(world.auto_supply_enabled)
	labels["hp"].text = "生命 %d / %d" % [p.hp, p.hp_max]
	var hp_ratio := float(p.hp) / float(maxi(1, p.hp_max))
	_set_bar("hp", p.hp, p.hp_max, Color("#c0504d").lerp(Color("#8fbf6a"), hp_ratio))

	var infection_text := "   感染 %d" % p.infection if p.infection > 0 else ""
	labels["needs"].text = "饱腹 %d   水分 %d%s" % [p.hunger, p.thirst, infection_text]
	_set_bar("hunger", p.hunger, 100, Color("#8a2f2a").lerp(Color("#c9a15a"), p.hunger / 100.0))
	_set_bar("thirst", p.thirst, 100, Color("#8a2f2a").lerp(Color("#5a9fc9"), p.thirst / 100.0))
	_set_bar("stamina", p.stamina, p.max_stamina, Color("#8a2f2a").lerp(Color("#d69b5a"), float(p.stamina) / float(maxi(1, p.max_stamina))))

	labels["stamina"].text = "体力 %d / %d" % [p.stamina, p.max_stamina]
	var mode := "跑步" if p.run_mode else "走路"
	labels["ap"].text = "行动点 %d   %s · 速度 %d" % [p.moves, mode, p.effective_speed(world.item_db)]
	labels["turn"].text = "回合 %d   %s" % [world.turn, _pack_summary()]
	var raid_state := "已撤离" if world.extracted else ("行动失败" if world.raid_failed or world.dead else "行动中")
	raid_label.text = "%s  ·  仓库 %d 件" % [raid_state, profile_stash.size()]
	threat_label.text = _threat_summary()
	var wielded_name := "空手" if p.wielded == null else world.item_name(p.wielded.type_id)
	var offhand_name := "空" if p.offhand == null else world.item_name(p.offhand.type_id)
	load_label.text = "主手 %s  副手 %s\n%s" % [wielded_name, offhand_name, _pack_summary()]

	var lines: Array[String] = []
	var start := maxi(0, world.log_lines.size() - 4)
	for i: int in range(start, world.log_lines.size()):
		lines.append(world.log_lines[i])
	log_label.text = "\n".join(lines)
	status_label.text = _status_text()
	interaction_label.text = _interaction_text()
	var primary_interaction := _primary_interaction()
	if action_buttons.size() > 1:
		var examine_button := action_buttons[1]
		examine_button.text = String(primary_interaction.get("button", "E 检查"))
		examine_button.tooltip_text = String(primary_interaction.get("hint", ""))
		examine_button.disabled = world.dead or world.raid_failed or world.extracted
	_refresh_equipment_panel()
	inv_panel.visible = inventory_open
	if inventory_overlay != null:
		inventory_overlay.visible = inventory_open
	if deployment_overlay != null:
		deployment_overlay.visible = deployment_open
		deployment_panel.visible = deployment_open
	bottom_panel.visible = not inventory_open and not deployment_open
	if inventory_open:
		_rebuild_inventory_panel()
	else:
		item_action_open = false
		item_action_item = null
		item_action_options.clear()


func _status_text() -> String:
	if world.won:
		return "已成功撤离。物资已带回基地。按 R 再次出发。" if world.extracted else "救援已到达。按 R 再次出发。"
	if world.raid_failed:
		return "撤离窗口已关闭。行动失败，按 R 再次出发。"
	if world.dead:
		return "行动失败。携带物资遗失。按 R 再次出发。"
	var near := 0
	for actor: Actor in world.actors:
		if actor != world.player and actor.alive and world.visible.has(actor.cell_pos):
			near += 1
	var threat := "   视野内：%d 只" % near if near > 0 else ""
	if world.player.cell_pos == world.extract_site:
		return "撤离点已到达。按 E 开始撤离。%s" % threat
	return "目标：搜索物资，到西侧撤离点。剩余 %d 回合。%s" % [world.raid_turns_left, threat]


func _threat_summary() -> String:
	var near := 0
	for actor: Actor in world.actors:
		if actor != world.player and actor.alive and world.visible.has(actor.cell_pos):
			near += 1
	if near == 0:
		return "威胁 低   ·   视野内 0"
	if near == 1:
		return "威胁 中   ·   视野内 1"
	return "威胁 高   ·   视野内 %d" % near


func _primary_interaction() -> Dictionary:
	if world.dead or world.raid_failed or world.extracted:
		return {"button": "行动结束", "hint": "按 R 再次出发"}
	var cell := world.player.cell_pos
	if cell == world.extract_site:
		return {"button": "E 撤离", "hint": "已到达撤离点，按 E 开始撤离"}
	var container := world.container_at(cell)
	if not container.is_empty():
		var container_name := String(container.get("name", "容器"))
		return {"button": "E 搜索", "hint": "%s就在脚下，按 E 搜索" % container_name}
	if cell == world.repair_site:
		return {"button": "E 修理", "hint": "已到达电台塔，按 E 检查维修条件"}
	for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var adjacent_container := world.container_at(cell + delta)
		if not adjacent_container.is_empty():
			var adjacent_name := String(adjacent_container.get("name", "容器"))
			return {"button": "E 搜索", "hint": "附近有%s，按 E 搜索" % adjacent_name}
		if world.is_closed_door(cell + delta):
			return {"button": "E 开门", "hint": "附近有关闭的门，按 E 推开"}
	return {"button": "E 检查", "hint": "附近没有可交互目标"}


func _interaction_text() -> String:
	var primary := _primary_interaction()
	var messages: Array[String] = [String(primary.get("hint", ""))]
	var ground := world.items_at(world.player.cell_pos)
	if not ground.is_empty():
		messages.append("脚下有 %d 件物品，按 , 拾取" % ground.size())
	for delta: Vector2i in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		var cell := world.player.cell_pos + delta
		var target := world.actor_at(cell)
		if target != null and target != world.player and world.visible.has(target.cell_pos):
			messages.append("附近有%s，点击目标或撞上去攻击" % target.name)
	return "\n".join(messages.slice(0, 2))


func _parts_have() -> int:
	var have := 0
	for part: String in World.REPAIR_PARTS:
		if world.player.has_item(part):
			have += 1
	return have


func _pack_summary() -> String:
	var p := world.player
	return "%.1f/%.1fkg  %.1f/%.1fL" % [
		p.total_weight(world.item_db), p.max_weight,
		float(p.total_volume(world.item_db)) / 1000.0, float(p.max_volume(world.item_db)) / 1000.0,
	]


# ================================================================ 物品栏

func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	if not inventory_open:
		_close_inventory_state()
	_refresh_ui()
	queue_redraw()


func _close_inventory() -> void:
	inventory_open = false
	_close_inventory_state()
	_refresh_ui()
	queue_redraw()


func _close_inventory_state() -> void:
	item_action_open = false
	item_action_item = null
	item_action_options.clear()
	if item_context_panel != null:
		item_context_panel.visible = false


func _on_action_button(action_id: String) -> void:
	match action_id:
		"loot":
			if world.player_loot():
				_after_action()
		"examine":
			if world.player_examine():
				_after_action()
		"inventory":
			_toggle_inventory()
		"wait":
			if world.player_wait():
				_after_action()
		"run":
			world.player_toggle_run()
			refresh_ui()


func _rebuild_inventory_panel() -> void:
	if inventory_list == null:
		return
	for child: Node in inventory_list.get_children():
		child.free()
	var p := world.player
	if item_action_open and item_action_item != null:
		inventory_list.columns = 1
		inv_label.text = "物品动作  /  %s\n选择一个动作，Esc 返回物品列表" % world.item_name(item_action_item.type_id)
		for i: int in item_action_options.size():
			var option: Dictionary = item_action_options[i]
			var button := _inventory_button("%s   %s" % [char("A".unicode_at(0) + i), option["label"]])
			button.custom_minimum_size.x = 510
			button.pressed.connect(_on_inventory_action_pressed.bind(i))
			inventory_list.add_child(button)
		return
	inventory_list.columns = 2
	inv_label.text = "物品栏  /  %d 件\n负重 %.1f / %.1f kg   空间 %.1f / %.1f L\n左键选择 · 右键动作 · 拖到装备位" % [
		p.inventory.size(), p.total_weight(world.item_db), p.max_weight,
		float(p.total_volume(world.item_db)) / 1000.0, float(p.max_volume(world.item_db)) / 1000.0,
	]
	if p.inventory.is_empty():
		_label(inventory_list, "背包为空", Vector2.ZERO, 13, Color("#7d9188"))
		return
	for i: int in p.inventory.size():
		var item: Item = p.inventory[i]
		var equipped := "  [手持]" if p.wielded == item else ""
		if p.offhand == item:
			equipped += "  [副手]"
		if p.worn.has(item):
			equipped += "  [穿戴]"
		var button := _inventory_button("%s   %-10s%s\n      %s" % [char("A".unicode_at(0) + i), world.item_name(item.type_id), equipped, _item_summary(item)], i)
		button.tooltip_text = world.item_name(item.type_id)
		button.pressed.connect(_on_inventory_item_pressed.bind(i))
		button.gui_input.connect(_on_inventory_item_gui_input.bind(i))
		inventory_list.add_child(button)


func _inventory_button(text: String, item_index: int = -1) -> ItemDragButton:
	var button := _new_item_drag_button()
	button.inventory_item_index = item_index
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(248, 58)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", Color("#c3d0b9"))
	button.add_theme_color_override("font_hover_color", Color("#ffffff"))
	button.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#283b40")))
	button.add_theme_stylebox_override("hover", _button_style(Color("#19343a"), Color("#83b6a7")))
	return button


func _on_inventory_item_pressed(index: int) -> void:
	if index < 0 or index >= world.player.inventory.size():
		return
	item_action_item = world.player.inventory[index]
	item_action_options = ItemActions.available(item_action_item, world.player, world)
	item_action_open = not item_action_options.is_empty()
	refresh_ui()


func _on_inventory_item_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	if index >= 0 and index < world.player.inventory.size():
		_open_item_context_menu(world.player.inventory[index])
	get_viewport().set_input_as_handled()


func _on_equipment_slot_gui_input(event: InputEvent, slot_id: String) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_RIGHT or not mouse_event.pressed:
		return
	var item := _equipped_item(slot_id)
	if item != null:
		_open_item_context_menu(item)
	get_viewport().set_input_as_handled()


func _equipped_item(slot_id: String) -> Item:
	if slot_id == "main_hand":
		return world.player.wielded
	if slot_id == "off_hand":
		return world.player.offhand
	return world.player.worn_in_slot(slot_id, world.item_db)


func _open_item_context_menu(item: Item) -> void:
	item_action_item = item
	item_action_options = ItemActions.available(item, world.player, world)
	item_action_open = false
	for child: Node in item_context_list.get_children():
		child.free()
	if item_action_options.is_empty():
		item_context_panel.visible = false
		return
	for i: int in item_action_options.size():
		var option: Dictionary = item_action_options[i]
		var button := _new_button()
		button.text = String(option.get("label", "操作"))
		button.custom_minimum_size = Vector2(208, 32)
		button.add_theme_font_size_override("font_size", 12)
		button.add_theme_color_override("font_color", Color("#c3d0b9"))
		button.add_theme_stylebox_override("normal", _button_style(Color("#101a1d"), Color("#31454a")))
		button.add_theme_stylebox_override("hover", _button_style(Color("#19343a"), Color("#83b6a7")))
		button.pressed.connect(_on_context_action_selected.bind(i))
		item_context_list.add_child(button)
	var menu_height := float(item_action_options.size() * 35 + 12)
	item_context_panel.size = Vector2(220, menu_height)
	item_context_list.size = Vector2(208, menu_height - 12)
	var mouse := get_viewport().get_mouse_position()
	var viewport_size := get_viewport_rect().size
	item_context_panel.position = Vector2(
		clampf(mouse.x, 0.0, viewport_size.x - item_context_panel.size.x),
		clampf(mouse.y, 0.0, viewport_size.y - item_context_panel.size.y))
	item_context_panel.visible = true


func _on_context_action_selected(index: int) -> void:
	item_context_panel.visible = false
	_on_inventory_action_pressed(index)


func _on_inventory_item_dropped_on_slot(item_index: int, target_slot: String) -> void:
	if item_index < 0 or item_index >= world.player.inventory.size():
		return
	var item := world.player.inventory[item_index]
	if _equipped_item(target_slot) == item:
		return
	var target_action := ""
	if target_slot == "main_hand" and world.player.can_wield_main(item, world.item_db):
		target_action = "wield"
	elif target_slot == "off_hand" and world.player.can_hold_offhand(item, world.item_db):
		target_action = "hold_offhand"
	elif (
		world.player.equipment_slot(item.prototype(world.item_db)) == target_slot
		and world.player.can_wear(item, world.item_db)
	):
		target_action = "wear"
	if target_action.is_empty():
		world.log_message("这件物品不能放入该装备位，或当前空间不足。")
		refresh_ui()
		return
	item_action_item = item
	item_action_options = ItemActions.available(item, world.player, world)
	for i: int in item_action_options.size():
		if String(item_action_options[i].get("id", "")) == target_action:
			_on_inventory_action_pressed(i)
			return
	world.log_message("该物品当前无法装备。")
	refresh_ui()


func _on_inventory_action_pressed(index: int) -> void:
	if index < 0 or index >= item_action_options.size():
		return
	var option: Dictionary = item_action_options[index]
	var acted := _execute_item_action(option)
	item_action_open = false
	item_action_item = null
	item_action_options.clear()
	if acted:
		_after_action()
	else:
		refresh_ui()


func _inventory_text() -> String:
	var p := world.player
	if item_action_open:
		var action_lines: Array[String] = ["—— %s 的动作（按字母选择，Esc 返回）——" % world.item_name(item_action_item.type_id)]
		for i: int in item_action_options.size():
			var option: Dictionary = item_action_options[i]
			action_lines.append("%s) %s" % [char("a".unicode_at(0) + i), option["label"]])
		return "\n".join(action_lines)
	var lines: Array[String] = ["—— 背包（按字母选物品，i/Esc 关闭）——"]
	if p.inventory.is_empty():
		lines.append("（空）")
		return "\n".join(lines)
	for i: int in p.inventory.size():
		var item: Item = p.inventory[i]
		var letter := char("a".unicode_at(0) + i)
		var name := world.item_name(item.type_id)
		var equipped := " [手]" if p.wielded == item else ""
		if p.worn.has(item):
			equipped += " [穿]"
		lines.append("%s) %s%s   %s" % [letter, name, equipped, _item_summary(item)])
		if i >= 25:
			lines.append("……")
			break
	return "\n".join(lines)


## 这件东西能干嘛——直接读 use_methods，加新物品不用改这里。
func _item_summary(item: Item) -> String:
	var proto: Dictionary = item.prototype(item_data)
	var melee: Dictionary = proto.get("melee", {})
	var parts: Array[String] = []
	for method: Variant in proto.get("use_methods", []):
		if typeof(method) != TYPE_DICTIONARY:
			continue
		var m: Dictionary = method
		match String(m.get("type", "")):
			"consume":
				if int(m.get("quench", 0)) > 0:
					parts.append("喝 +%d" % int(m["quench"]))
				if int(m.get("calories", 0)) > 0:
					parts.append("吃 +%d" % int(m["calories"]))
			"heal":
				if int(m.get("heal", 0)) > 0:
					parts.append("治 +%d" % int(m["heal"]))
				if int(m.get("cure", 0)) > 0:
					parts.append("抗感染 +%d" % int(m["cure"]))
			"transform":
				parts.append("开关")
			_:
				parts.append(String(m.get("type", "")))
	if melee.has("damage"):
		parts.append("伤害 %d" % int(melee["damage"]))
	if proto.has("armor"):
		parts.append("护甲 %d" % int(proto["armor"]))
	if proto.has("weight") or proto.has("volume"):
		var packed := item != world.player.wielded and item != world.player.offhand and not world.player.worn.has(item)
		var volume := float(proto.get("volume", 0)) / 1000.0 if packed else 0.0
		parts.append("%.1fkg 占包 %.1fL" % [float(proto.get("weight", 0.0)), volume])
	if proto.has("capacity_volume"):
		parts.append("+%.1fL容量" % (float(proto["capacity_volume"]) / 1000.0))
	if parts.is_empty():
		return "—"
	return "｜".join(parts)


# ================================================================ 渲染

func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown = maxf(0.0, _move_cooldown - delta)
	if mouse_destination.x >= 0 and not inventory_open:
		mouse_move_timer -= delta
		if mouse_move_timer <= 0.0:
			mouse_move_timer = MOUSE_MOVE_INTERVAL
			_continue_mouse_move()
	if camera == null:
		return
	if not inventory_open:
		var next_hover := _cell_from_mouse()
		if next_hover != hover_cell:
			hover_cell = next_hover
			queue_redraw()
	# 一格一格的位置用指数平滑抹成滑动，别让它跳。
	var k: float = 1.0 - exp(-delta * MOVE_SMOOTH)
	for actor: Actor in world.actors:
		var target := _iso(actor.free_pos)
		var current: Vector2 = _visual.get(actor.id, target)
		_visual[actor.id] = current.lerp(target, k)
	var view := get_viewport_rect().size / camera.zoom
	var half := view / 2.0
	var target_pos := _actor_world_pos(world.player) + Vector2(0, ISO_H / 2.0)
	var bounds := _map_bounds()
	if bounds.size.x > view.x:
		target_pos.x = clampf(target_pos.x, bounds.position.x + half.x, bounds.end.x - half.x)
	else:
		target_pos.x = bounds.get_center().x
	if bounds.size.y > view.y:
		target_pos.y = clampf(target_pos.y, bounds.position.y + half.y, bounds.end.y - half.y)
	else:
		target_pos.y = bounds.get_center().y
	camera.position = target_pos


## 第 (x,y) 格的菱形顶点在屏幕上的位置（2:1 等距）。
func _iso(cell: Vector2) -> Vector2:
	return Vector2((cell.x - cell.y) * ISO_W / 2.0, (cell.x + cell.y) * ISO_H / 2.0)


func _map_bounds() -> Rect2:
	var left := _iso(Vector2i(0, H - 1)).x - ISO_W / 2.0
	var right := _iso(Vector2i(W - 1, 0)).x + ISO_W / 2.0
	var top := -WALL_H - ISO_H
	var bottom := _iso(Vector2i(W - 1, H - 1)).y + ISO_H * 1.5
	return Rect2(left, top, right - left, bottom - top)


func _actor_world_pos(actor: Actor) -> Vector2:
	return _visual.get(actor.id, _iso(actor.free_pos))


func _actor_center(actor: Actor) -> Vector2:
	return _actor_world_pos(actor) + Vector2(0, ISO_H / 2.0)


func _draw() -> void:
	draw_rect(Rect2(-4000, -4000, 12000, 12000), Color("#05080a"))
	# 1) 地板：等距菱形，先全部铺一遍（它们不互相遮挡）。
	for y: int in H:
		for x: int in W:
			var cell := Vector2i(x, y)
			if not world.seen.has(cell) or world.is_wall(cell):
				continue
			_draw_floor(cell)
	# 2) 见过但当前看不见的地方压暗（墙由方块自己压暗，别在它脚下再刷一层黑）。
	for y: int in H:
		for x: int in W:
			var cell := Vector2i(x, y)
			if world.is_wall(cell):
				continue
			if world.seen.has(cell) and not world.visible.has(cell):
				_draw_fog(cell)
	# 3) 立起来的东西：按 (x+y) 从远到近画，前面自然盖住后面。
	var cells: Array[Vector2i] = []
	for y: int in H:
		for x: int in W:
			var cell := Vector2i(x, y)
			if world.seen.has(cell):
				cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x + a.y == b.x + b.y:
			return a.x < b.x
		return a.x + a.y < b.x + b.y)
	for cell: Vector2i in cells:
		_draw_cell_objects(cell)
	# 电台塔上的修理点；只画玩家看见时。
	if world.visible.has(world.repair_site):
		var pts := _diamond(_iso(world.repair_site))
		pts.append(pts[0])
		draw_polyline(pts, Color("#eecb80"), 2.0)
	if world.visible.has(world.extract_site):
		var exit_pts := _diamond(_iso(world.extract_site))
		exit_pts.append(exit_pts[0])
		draw_polyline(exit_pts, Color("#eecb80"), 3.0)
	if not inventory_open and world.in_bounds(hover_cell) and world.visible.has(hover_cell):
		var hover := _diamond(_iso(hover_cell))
		hover.append(hover[0])
		draw_polyline(hover, Color(0.45, 0.78, 0.7, 0.72), 2.0)
	_draw_move_preview()


func _draw_move_preview() -> void:
	if inventory_open:
		return
	var destination_cell := mouse_destination
	var destination_position := mouse_destination_position
	if destination_cell.x < 0:
		destination_cell = hover_cell
		if not world.in_bounds(destination_cell) or not world.visible.has(destination_cell):
			return
		destination_position = Vector2(destination_cell)
	var path := world.find_path(world.player.pos, destination_cell, world.player)
	if path.is_empty():
		return
	var ground_offset := Vector2(0, ISO_H / 2.0)
	var route := PackedVector2Array([world.player.free_pos])
	for index: int in range(1, path.size()):
		route.append(Vector2(path[index]))
	if route[route.size() - 1].distance_to(destination_position) > 0.01:
		route.append(destination_position)
	var points := PackedVector2Array()
	for position: Vector2 in route:
		points.append(_iso(position) + ground_offset)
	if points.size() > 1:
		draw_polyline(points, Color(0.55, 0.86, 0.76, 0.78), 3.0, true)
	var moves_per_tile := 50.0 if world.player.run_mode else 100.0
	if _route_cost(route, moves_per_tile) > float(world.player.moves):
		var stop_position := _position_after_movement(route, world.player.moves, moves_per_tile)
		var stop_screen := _iso(stop_position) + ground_offset
		draw_arc(stop_screen, 9.0, 0.0, TAU, 24, Color(0.95, 0.79, 0.45, 0.95), 2.0, true)
	var destination_screen := _iso(destination_position) + ground_offset
	draw_circle(destination_screen, 4.0, Color(0.72, 0.95, 0.81, 0.92))


func _position_after_movement(route: PackedVector2Array, moves: int, moves_per_tile: float) -> Vector2:
	var moves_left := maxf(0.0, float(moves))
	for index: int in range(1, route.size()):
		var start := route[index - 1]
		var finish := route[index]
		var finish_cell := world.cell_at(finish)
		if world.is_closed_door(finish_cell):
			var start_cell := world.cell_at(start)
			var door_entry := Vector2(start_cell).lerp(Vector2(finish_cell), 0.5)
			var approach_cost := start.distance_to(door_entry) * moves_per_tile
			if approach_cost > moves_left:
				return start.lerp(door_entry, moves_left / approach_cost)
			moves_left -= approach_cost
			start = door_entry
			if moves_left > 0.0:
				var door_cost := 50.0 if moves_per_tile == 50.0 else 100.0
				moves_left = maxf(0.0, moves_left - door_cost)
			if moves_left <= 0.0:
				return door_entry
		var segment_cost := start.distance_to(finish) * moves_per_tile
		if segment_cost > moves_left:
			return start.lerp(finish, moves_left / segment_cost)
		moves_left -= segment_cost
	return route[route.size() - 1]


func _route_length(route: PackedVector2Array) -> float:
	var total := 0.0
	for index: int in range(1, route.size()):
		total += route[index - 1].distance_to(route[index])
	return total


func _route_cost(route: PackedVector2Array, moves_per_tile: float) -> float:
	var total := _route_length(route) * moves_per_tile
	for index: int in range(1, route.size()):
		if world.is_closed_door(world.cell_at(route[index])):
			total += 50.0 if moves_per_tile == 50.0 else 100.0
	return total


## 一格里立起来/摆在平面上的东西：墙、关着的门、地面物品、角色。
func _draw_cell_objects(cell: Vector2i) -> void:
	var visible := world.visible.has(cell)
	var mod := TINT if visible else TINT.darkened(0.55)
	if world.is_wall(cell):
		_draw_block(cell, "wall", WALL_H, mod)
	elif world.is_closed_door(cell):
		_draw_block(cell, "door_closed", DOOR_H, mod)
	if visible:
		for item: Dictionary in world.items:
			if item["pos"] == cell:
				_draw_item(String(item["id"]), cell)
		if not world.container_at(cell).is_empty():
			_draw_container(cell)
	for actor: Actor in world.actors:
		if actor.cell_pos != cell or not actor.alive:
			continue
		if actor != world.player and not visible:
			continue
		_draw_actor(actor)


func _diamond(origin: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		origin + Vector2(0, 0),
		origin + Vector2(ISO_W / 2.0, ISO_H / 2.0),
		origin + Vector2(0, ISO_H),
		origin + Vector2(-ISO_W / 2.0, ISO_H / 2.0),
	])


func _floor_name(cell: Vector2i) -> String:
	if world.is_door(cell):
		return "door_open" if world.doors_open.has(cell) else "door_closed"
	return world.terrain_name(cell)


func _draw_floor(cell: Vector2i) -> void:
	var name := _floor_name(cell)
	var at := int(iso_cells.get(name, -1))
	var origin := _iso(cell) - Vector2(ISO_W / 2.0, 0)
	if iso_texture == null or at < 0:
		draw_colored_polygon(_diamond(_iso(cell)), Color("#1b2a33"))
		return
	draw_texture_rect_region(iso_texture,
		Rect2(origin, Vector2(ISO_W, ISO_H)),
		Rect2(at * ISO_W, 0, ISO_W, ISO_H), TINT)


func _draw_fog(cell: Vector2i) -> void:
	draw_colored_polygon(_diamond(_iso(cell)), Color(0.02, 0.03, 0.04, 0.62))


## 一个方块：两个侧面 + 顶面。看起来像有高度的墙。
func _draw_block(cell: Vector2i, texture_name: String, height: float, mod: Color) -> void:
	var top := _iso(cell)
	var left := top + Vector2(-ISO_W / 2.0, ISO_H / 2.0)
	var right := top + Vector2(ISO_W / 2.0, ISO_H / 2.0)
	var bottom := top + Vector2(0, ISO_H)
	var up := Vector2(0, -height)
	draw_colored_polygon(PackedVector2Array([left, bottom, bottom + up, left + up]),
		Color(0.26, 0.22, 0.19) * mod)
	draw_colored_polygon(PackedVector2Array([bottom, right, right + up, bottom + up]),
		Color(0.17, 0.145, 0.13) * mod)
	var at := int(iso_cells.get(texture_name, -1))
	if iso_texture == null or at < 0:
		draw_colored_polygon(PackedVector2Array([top + up, right + up, bottom + up, left + up]),
			Color("#2a2a2a") * mod)
		return
	draw_texture_rect_region(iso_texture,
		Rect2(top + up - Vector2(ISO_W / 2.0, 0), Vector2(ISO_W, ISO_H)),
		Rect2(at * ISO_W, 0, ISO_W, ISO_H), mod)


func _draw_item(item_id: String, cell: Vector2i) -> void:
	var at: Array = _tile_cells("item_" + item_id, 0)
	var center := _iso(cell) + Vector2(0, ISO_H * 0.5)
	if at.is_empty() or tile_texture == null:
		draw_rect(Rect2(center - Vector2(6, 6), Vector2(12, 12)), Color("#eecb80"))
		return
	var size := Vector2(34, 34)
	draw_texture_rect_region(tile_texture,
		Rect2(center - Vector2(size.x / 2.0, size.y / 2.0 + 8), size),
		Rect2(float(at[0]) * CELL, float(at[1]) * CELL, CELL, CELL), TINT)


func _draw_container(cell: Vector2i) -> void:
	var center := _iso(cell) + Vector2(0, ISO_H * 0.5)
	draw_rect(Rect2(center - Vector2(10, 8), Vector2(20, 16)), Color("#273e42"))
	draw_rect(Rect2(center - Vector2(10, 8), Vector2(20, 16)), Color("#83b6a7"), false, 1.5)


## 同一块地形有几个变体就按坐标轮换，别让整条街看起来像一张贴图。
func _tile_cells(name: String, variant: int) -> Array:
	var tiles: Dictionary = tiles_meta.get("tiles", {})
	if tile_texture == null or not tiles.has(name):
		return []
	var cells: Array = tiles[name]
	if cells.is_empty():
		return []
	return cells[variant % cells.size()]


func _variant(_cell: Vector2i) -> int:
	# UltiCa 的 multitile 4 张是「一块图案的四个角」，不是可互换的变体，
	# 按坐标乱轮会把地板拼成楼梯。统一用第 0 张。
	return 0


## 角色是立绘：脚踩在菱形中心，按 1.5 倍画，跟 64×32 的地砖比例协调。
func _draw_actor(actor: Actor) -> void:
	var center := _actor_center(actor)
	var name := "player" if actor.is_player else actor.monster_type
	var frames: Dictionary = tiles_meta.get("actors", {}).get("frames", {})
	if actor_texture == null or not frames.has(name):
		draw_circle(center, 10, Color("#9fe4bb"))
		return
	var index := int(frames[name])
	var size := Vector2(CELL * ACTOR_SCALE, ACTOR_H * ACTOR_SCALE)
	draw_texture_rect_region(actor_texture,
		Rect2(center.x - size.x / 2.0, center.y - size.y + 6, size.x, size.y),
		Rect2(index * CELL, 0, CELL, ACTOR_H))


# ================================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	if deployment_open:
		return
	if item_context_panel != null and item_context_panel.visible:
		if event is InputEventMouseButton and event.pressed:
			if not item_context_panel.get_global_rect().has_point(event.position):
				item_context_panel.visible = false
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			item_context_panel.visible = false
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		_handle_map_click(event as InputEventMouseButton)
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := (event as InputEventKey).keycode

	if inventory_open:
		if _handle_inventory_key(key):
			_after_action()
		return
	# CDDA 里按住方向键会一直走；这里放行方向键的连发，其它键只要按一次。
	if event.echo and not _is_move_key(key):
		return
	if _is_move_key(key):
		if _move_cooldown > 0.0:
			return
		_move_cooldown = 0.08

	match key:
		KEY_W, KEY_UP, KEY_K, KEY_KP_8:
			_move_player_free(Vector2.UP)
		KEY_S, KEY_DOWN, KEY_J, KEY_KP_2:
			_move_player_free(Vector2.DOWN)
		KEY_A, KEY_LEFT, KEY_H, KEY_KP_4:
			_move_player_free(Vector2.LEFT)
		KEY_D, KEY_RIGHT, KEY_L, KEY_KP_6:
			_move_player_free(Vector2.RIGHT)
		KEY_Y, KEY_KP_7:
			_move_player_free(Vector2(-1, -1))
		KEY_U, KEY_KP_9:
			_move_player_free(Vector2(1, -1))
		KEY_B, KEY_KP_1:
			_move_player_free(Vector2(-1, 1))
		KEY_N, KEY_KP_3:
			_move_player_free(Vector2(1, 1))
		KEY_I:
			inventory_open = true
		KEY_COMMA:
			world.player_loot()
		KEY_E:
			world.player_examine()
		KEY_PERIOD, KEY_5, KEY_SPACE:
			world.player_wait()
		KEY_APOSTROPHE, KEY_QUOTEDBL:
			world.player_toggle_run()
		KEY_F5:
			_save()
		KEY_F9:
			_load()
		KEY_R:
			_start_new_raid()
	_after_action()


func _input(event: InputEvent) -> void:
	if item_context_panel == null or not item_context_panel.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if not item_context_panel.get_global_rect().has_point(event.position):
			item_context_panel.visible = false
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		item_context_panel.visible = false
		get_viewport().set_input_as_handled()


func _handle_map_click(event: InputEventMouseButton) -> void:
	if inventory_open:
		return
	var cell := _cell_from_mouse()
	var destination_position := _position_from_mouse()
	if not world.in_bounds(cell):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		var target := world.actor_at(cell)
		if target != null and target != world.player:
			world.log_message("目标：%s，HP %d/%d。" % [target.name, target.hp, target.hp_max])
		elif world.is_wall(cell):
			world.log_message("这里是墙。")
		elif world.is_closed_door(cell):
			world.log_message("关闭的门。按 E 或左键互动。")
		else:
			world.log_message("地面：%s。" % world.terrain_name(cell))
		refresh_ui()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var container := world.container_at(cell)
	if not container.is_empty():
		mouse_destination = cell
		mouse_destination_position = Vector2(cell)
		mouse_search_container = true
		mouse_move_timer = 0.0
		return
	if cell == world.extract_site:
		mouse_destination = cell
		mouse_destination_position = Vector2(cell)
		mouse_search_container = false
		mouse_move_timer = 0.0
		return
	var target := world.actor_at(cell)
	if target != null and target != world.player:
		mouse_destination = Vector2i(-999, -999)
		if world.player_attack(target):
			_after_action()
		return
	if cell == world.player.pos and not world.items_at(cell).is_empty():
		mouse_destination = Vector2i(-999, -999)
		if world.player_loot():
			_after_action()
		return
	mouse_destination = cell
	mouse_destination_position = destination_position
	mouse_move_timer = 0.0


func _move_player_free(direction: Vector2) -> void:
	mouse_destination = Vector2i(-999, -999)
	mouse_search_container = false
	if world.player_move_direction(direction, 0.2):
		_after_action()


func _continue_mouse_move() -> void:
	if mouse_destination == Vector2i(-999, -999):
		return
	if world.player.free_pos.distance_to(mouse_destination_position) <= 0.03:
		if mouse_search_container:
			var container := world.container_at(mouse_destination)
			mouse_search_container = false
			mouse_destination = Vector2i(-999, -999)
			if not container.is_empty() and world.player_search_container(container):
				_after_action()
			return
		mouse_destination = Vector2i(-999, -999)
		return
	var next_step := _next_path_step(world.player.pos, mouse_destination)
	if next_step == Vector2i.ZERO and world.player.pos != mouse_destination:
		mouse_destination = Vector2i(-999, -999)
		mouse_search_container = false
		return
	var target_position := mouse_destination_position
	if next_step != Vector2i.ZERO:
		target_position = Vector2(world.player.pos + next_step)
	var toward: Vector2 = target_position - world.player.free_pos
	var step_distance := minf(0.2, toward.length())
	if step_distance <= 0.02:
		return
	if not world.player_move_direction(toward, step_distance):
		mouse_destination = Vector2i(-999, -999)
		mouse_search_container = false
		return
	_after_action()


func _next_path_step(from: Vector2i, to: Vector2i) -> Vector2i:
	var path := world.find_path(from, to, world.player)
	if path.size() < 2:
		return Vector2i.ZERO
	return path[1] - path[0]


func _cell_from_mouse() -> Vector2i:
	var point := _position_from_mouse()
	return Vector2i(roundi(point.x), roundi(point.y))


func _position_from_mouse() -> Vector2:
	var point := get_global_mouse_position()
	var axial_x := point.x / (ISO_W / 2.0)
	var axial_y := point.y / (ISO_H / 2.0)
	return Vector2((axial_x + axial_y) * 0.5, (axial_y - axial_x) * 0.5)


func _is_move_key(key: int) -> bool:
	return key in [
		KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
		KEY_H, KEY_J, KEY_K, KEY_L, KEY_Y, KEY_U, KEY_B, KEY_N,
		KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9,
	]


func _handle_inventory_key(key: int) -> bool:
	if item_action_open:
		if key == KEY_ESCAPE or key == KEY_I:
			item_action_open = false
			item_action_item = null
			item_action_options.clear()
			refresh_ui()
			return false
		if key < KEY_A or key > KEY_Z:
			return false
		var action_index: int = key - KEY_A
		if action_index < 0 or action_index >= item_action_options.size():
			return false
		var option: Dictionary = item_action_options[action_index]
		var acted := _execute_item_action(option)
		item_action_open = false
		item_action_item = null
		item_action_options.clear()
		return acted
	if key == KEY_I or key == KEY_ESCAPE:
		_close_inventory()
		return false
	if key < KEY_A or key > KEY_Z:
		return false
	var index: int = key - KEY_A
	var items := world.player.inventory
	if index < 0 or index >= items.size():
		return false
	item_action_item = items[index]
	item_action_options = ItemActions.available(item_action_item, world.player, world)
	if item_action_options.is_empty():
		world.log_message("这件东西现在没有可用动作。")
		return false
	item_action_open = true
	refresh_ui()
	return false


func _execute_item_action(option: Dictionary) -> bool:
	if item_action_item == null:
		return false
	var action_id := String(option.get("id", ""))
	var method: Dictionary = option.get("method", {})
	match action_id:
		"use":
			return world.player_use_method(item_action_item, method)
		"wield":
			return world.player_wield(item_action_item)
		"unwield":
			return world.player_unwield()
		"hold_offhand":
			return world.player_hold_offhand(item_action_item)
		"unhold_offhand":
			return world.player_unhold_offhand()
		"wear":
			return world.player_wear(item_action_item)
		"unwear":
			return world.player_unwear(item_action_item)
		"drop":
			return world.player_drop(item_action_item)
		"disassemble":
			return world.player_disassemble(item_action_item)
	return false


func _after_action() -> void:
	world.settle()
	if not profile_outcome_saved and (world.extracted or world.dead or world.raid_failed):
		profile_stash = world.stash.duplicate()
		_save_profile()
		profile_outcome_saved = true
	refresh_ui()


func _start_new_raid() -> void:
	var auto_supply_enabled := world.auto_supply_enabled
	world = World.new(item_data, monster_data)
	world.auto_supply_enabled = auto_supply_enabled
	world.stash = profile_stash.duplicate()
	profile_outcome_saved = false
	_visual.clear()
	mouse_destination = Vector2i(-999, -999)
	mouse_search_container = false
	_close_inventory_state()
	inventory_open = false
	_open_deployment_screen()
	refresh_ui()


## 让外部（截图工具、将来的 UI 层）能强制刷新一次。
func refresh_ui() -> void:
	_refresh_ui()
	queue_redraw()


func _save() -> void:
	var file := FileAccess.open("user://save.json", FileAccess.WRITE)
	if file == null:
		world.log_message("存档失败。")
		return
	file.store_string(JSON.stringify(world.to_dict()))
	world.log_message("已存档。")


func _load() -> void:
	var file := FileAccess.open("user://save.json", FileAccess.READ)
	if file == null:
		world.log_message("没有存档。")
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		world.log_message("存档损坏。")
		return
	if not world.from_dict(parsed):
		world.log_message("存档版本不认，按 R 重开。")
		return
	_visual.clear()
	mouse_destination = Vector2i(-999, -999)
	mouse_search_container = false
	profile_stash = world.stash.duplicate()
	_save_profile()
	world.log_message("已读档。")
