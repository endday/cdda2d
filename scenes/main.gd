extends Node2D
## CDDA2D 适配层：2D 俯视、FOV、HUD、输入、物品栏。
## 规则在 World + Action + ItemUse；这里只画和翻译输入。
## 贴图来自 CDDA 的 UltiCa tileset（CC BY-SA 3.0，见 content/tiles/CREDITS.md）。

const CELL := 32
const ACTOR_H := 48
const W := World.W
const H := World.H
const ZOOM := 1.5
const MOVE_SMOOTH := 16.0    # 越大越跟手；16 ≈ 0.15 秒走完一格

var world: World
var camera: Camera2D
var labels: Dictionary = {}
var bars: Dictionary = {}
var log_label: Label
var status_label: Label
var hint_label: Label

var inv_panel: Panel
var inv_label: Label
var inventory_open := false

var tile_texture: Texture2D
var actor_texture: Texture2D
var tiles_meta: Dictionary = {}
var ui_font: FontFile

## 每个 Actor 的屏幕位置（世界像素），用来把一格一格的跳变抹成滑动。
var _visual: Dictionary = {}
var _move_cooldown := 0.0     # 按住方向键时限制节奏，别让动画追不上

var item_data: Dictionary = {}
var monster_data: Dictionary = {}

## 整体压一点冷色，别让 UltiCa 的木地板太橘。
const TINT := Color(0.82, 0.85, 0.9)


func _ready() -> void:
	var items := _load_json_array("res://content/items.json")
	var monsters := _load_json_array("res://content/monsters.json")
	_validate_content(items, monsters)
	item_data = ContentDB.index_by_id(items)
	monster_data = ContentDB.index_by_id(monsters)
	world = World.new(item_data, monster_data)
	_load_tiles()
	_load_font()
	_build_camera()
	_build_ui()
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


## 内容有问题就别猜，直接报到日志里，方便测试和 CI 抓。
func _validate_content(items: Array, monsters: Array) -> void:
	var problems: Array[String] = []
	problems.append_array(ContentDB.validate_items(items))
	problems.append_array(ContentDB.validate_monsters(monsters))
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


## Web 端没有系统字体兜底，必须自带一份中文字体子集（tools/build_font.py）。
func _load_font() -> void:
	var resource: Resource = load("res://content/fonts/ui.otf")
	if resource is FontFile:
		ui_font = resource
	else:
		push_error("content/fonts/ui.otf 读不到，中文会变方块")


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.position = _actor_world_pos(world.player)
	camera.zoom = Vector2(ZOOM, ZOOM)
	add_child(camera)


# ================================================================ HUD

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := _panel(layer, Rect2(18, 18, 300, 142))
	labels["hp"] = _label(panel, "", Vector2(14, 10), 15, Color("#e8f1ea"))
	bars["hp"] = _bar(panel, Vector2(14, 34), Vector2(272, 10), Color("#c0504d"))
	labels["needs"] = _label(panel, "", Vector2(14, 52), 13, Color("#c8d6c0"))
	bars["hunger"] = _bar(panel, Vector2(14, 76), Vector2(132, 8), Color("#c9a15a"))
	bars["thirst"] = _bar(panel, Vector2(154, 76), Vector2(132, 8), Color("#5a9fc9"))
	labels["ap"] = _label(panel, "", Vector2(14, 92), 13, Color("#9fd4c4"))
	labels["turn"] = _label(panel, "", Vector2(14, 114), 12, Color("#7d9188"))

	var log_panel := _panel(layer, Rect2(18, 584, 560, 92))
	log_label = _label(log_panel, "", Vector2(14, 8), 13, Color("#c3d0b9"))
	log_label.size = Vector2(532, 76)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	status_label = _label(layer, "", Vector2(336, 24), 14, Color("#eecb80"))
	hint_label = _label(layer,
		"WASD/方向键 走（撞门推开、撞怪就砍）   i 背包   , 搜   e 交互/修电台   . 等   F5 存   F9 读   R 重开",
		Vector2(18, 690), 12, Color("#7d9188"))
	# CC BY-SA 要求署名：把这行留在画面里，别只写在 README。
	_label(layer, "Tiles: Cataclysm DDA UltiCa, CC BY-SA 3.0",
		Vector2(940, 704), 11, Color("#7d9188"))

	inv_panel = _panel(layer, Rect2(18, 176, 340, 396))
	inv_panel.visible = false
	inv_label = _label(inv_panel, "", Vector2(14, 10), 13, Color("#c3d0b9"))
	inv_label.size = Vector2(312, 372)


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
	if ui_font != null:
		label.add_theme_font_override("font", ui_font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


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
	labels["hp"].text = "HP %d / %d" % [p.hp, p.hp_max]
	var hp_ratio := float(p.hp) / float(maxi(1, p.hp_max))
	_set_bar("hp", p.hp, p.hp_max, Color("#c0504d").lerp(Color("#8fbf6a"), hp_ratio))

	var infection_text := "   感染 %d" % p.infection if p.infection > 0 else ""
	labels["needs"].text = "饥饿 %d   口渴 %d%s" % [p.hunger, p.thirst, infection_text]
	_set_bar("hunger", p.hunger, 100, Color("#8a2f2a").lerp(Color("#c9a15a"), p.hunger / 100.0))
	_set_bar("thirst", p.thirst, 100, Color("#8a2f2a").lerp(Color("#5a9fc9"), p.thirst / 100.0))

	labels["ap"].text = "moves %d  速度 %d  背包 %d 件" % [p.moves, p.speed, p.inventory.size()]
	labels["turn"].text = "回合 %d   %s" % [world.turn, _pack_summary()]

	var lines: Array[String] = []
	var start := maxi(0, world.log_lines.size() - 4)
	for i: int in range(start, world.log_lines.size()):
		lines.append(world.log_lines[i])
	log_label.text = "\n".join(lines)
	status_label.text = _status_text()
	inv_panel.visible = inventory_open
	if inventory_open:
		inv_label.text = _inventory_text()


func _status_text() -> String:
	if world.won:
		return "救援到了。第 %d 回合，你活下来了。按 R 再来一局。" % world.turn
	if world.dead:
		return "你倒下了。撑到第 %d 回合。按 R 重开。" % world.turn
	var near := 0
	for actor: Actor in world.actors:
		if actor != world.player and actor.alive and world.visible.has(actor.pos):
			near += 1
	var threat := "   视野内：%d 只" % near if near > 0 else ""
	if world.radio_fixed:
		return "守住 %d 回合！%s" % [world.defense_left, threat]
	if not world.activity.is_empty():
		return "修理中……还剩 %d 回合，别乱动。%s" % [int(world.activity["turns_left"]), threat]
	return "目标：找齐 零件/电池/电线（%d/3），站到电台塔上按 e 修。%s" % [_parts_have(), threat]


func _parts_have() -> int:
	var have := 0
	for part: String in World.REPAIR_PARTS:
		if world.player.has_item(part):
			have += 1
	return have


func _pack_summary() -> String:
	var p := world.player
	if p.inventory.is_empty():
		return "背包空"
	var names: Array[String] = []
	for item: Item in p.inventory.slice(0, 5):
		names.append(world.item_name(item.type_id))
	return "背包：" + ", ".join(names)


# ================================================================ 物品栏

func _toggle_inventory() -> void:
	inventory_open = not inventory_open
	_refresh_ui()
	queue_redraw()


func _inventory_text() -> String:
	var p := world.player
	var lines: Array[String] = ["—— 背包（按字母使用，i/Esc 关闭）——"]
	if p.inventory.is_empty():
		lines.append("（空）")
		return "\n".join(lines)
	for i: int in p.inventory.size():
		var item: Item = p.inventory[i]
		var letter := char("a".unicode_at(0) + i)
		var name := world.item_name(item.type_id)
		lines.append("%s) %s   %s" % [letter, name, _item_summary(item)])
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
	if parts.is_empty():
		return "—"
	return "｜".join(parts)


# ================================================================ 渲染

func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown = maxf(0.0, _move_cooldown - delta)
	if camera == null:
		return
	# 一格一格的位置用指数平滑抹成滑动，别让它跳。
	var k: float = 1.0 - exp(-delta * MOVE_SMOOTH)
	for actor: Actor in world.actors:
		var target := Vector2(actor.pos) * CELL
		var current: Vector2 = _visual.get(actor.id, target)
		_visual[actor.id] = current.lerp(target, k)
	var view := get_viewport_rect().size / camera.zoom
	var half := view / 2.0
	var target_pos := _actor_world_pos(world.player) + Vector2(CELL / 2.0, CELL / 2.0)
	if W * CELL > view.x:
		target_pos.x = clampf(target_pos.x, half.x, W * CELL - half.x)
	if H * CELL > view.y:
		target_pos.y = clampf(target_pos.y, half.y, H * CELL - half.y)
	camera.position = target_pos


func _actor_world_pos(actor: Actor) -> Vector2:
	return _visual.get(actor.id, Vector2(actor.pos) * CELL)


func _actor_center(actor: Actor) -> Vector2:
	return _actor_world_pos(actor) + Vector2(CELL / 2.0, CELL / 2.0)


func _draw() -> void:
	draw_rect(Rect2(0, 0, W * CELL, H * CELL), Color("#05080a"))
	for y: int in H:
		for x: int in W:
			var cell := Vector2i(x, y)
			if not world.seen.has(cell):
				continue
			var origin := Vector2(x * CELL, y * CELL)
			_draw_tile(world.terrain_name(cell), cell)
			if not world.visible.has(cell):
				draw_rect(Rect2(origin, Vector2(CELL, CELL)), Color(0.02, 0.03, 0.04, 0.62))
	for item: Dictionary in world.items:
		var pos: Vector2i = item["pos"]
		if not world.visible.has(pos):
			continue
		_draw_item(String(item["id"]), Vector2(pos) * CELL)
	# 怪物：只画玩家看得见的（数据边界，别偷看世界）。
	for actor: Actor in world.actors:
		if actor == world.player or not actor.alive:
			continue
		if not world.visible.has(actor.pos):
			continue
		_draw_actor_at(actor.monster_type, _actor_world_pos(actor))
	_draw_actor_at("player", _actor_world_pos(world.player))
	# 电台塔上的修理点；只画玩家看见时。
	if world.visible.has(world.repair_site):
		var site := Rect2(Vector2(world.repair_site) * CELL, Vector2(CELL, CELL))
		draw_rect(site.grow(-3), Color("#eecb80"), false, 2.0)


func _draw_tile(name: String, cell: Vector2i) -> void:
	var at: Array = _tile_cells(name, _variant(cell))
	var origin := Vector2(cell) * CELL
	if at.is_empty():
		# 没有贴图就退回纯色，至少看得懂。
		var fallback := Color("#1b2a33")
		if name == "wall" or name == "rock":
			fallback = Color("#0a1014")
		elif name == "door_closed" or name == "door_open":
			fallback = Color("#eecb80")
		draw_rect(Rect2(origin, Vector2(CELL, CELL)), fallback)
		return
	draw_texture_rect_region(tile_texture,
		Rect2(origin, Vector2(CELL, CELL)),
		Rect2(float(at[0]) * CELL, float(at[1]) * CELL, CELL, CELL), TINT)


func _draw_item(item_id: String, origin: Vector2) -> void:
	var at: Array = _tile_cells("item_" + item_id, 0)
	if at.is_empty():
		draw_rect(Rect2(origin + Vector2(9, 9), Vector2(14, 14)), Color("#eecb80"))
		return
	draw_texture_rect_region(tile_texture,
		Rect2(origin, Vector2(CELL, CELL)),
		Rect2(float(at[0]) * CELL, float(at[1]) * CELL, CELL, CELL), TINT)


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


func _draw_actor_at(name: String, origin: Vector2) -> void:
	var actors: Dictionary = tiles_meta.get("actors", {})
	var frames: Dictionary = actors.get("frames", {})
	if actor_texture == null or not frames.has(name):
		draw_circle(origin + Vector2(CELL / 2.0, CELL / 2.0), 11, Color("#9fe4bb"))
		return
	var index := int(frames[name])
	# 角色图是 32×48，脚在格子底部。
	var top := Vector2(origin.x, origin.y + CELL - ACTOR_H)
	draw_texture_rect_region(actor_texture,
		Rect2(top, Vector2(CELL, ACTOR_H)),
		Rect2(index * CELL, 0, CELL, ACTOR_H))


# ================================================================ 输入

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	var key := (event as InputEventKey).keycode

	if inventory_open:
		_handle_inventory_key(key)
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
		KEY_W, KEY_UP:
			world.player_step(0, -1)
		KEY_S, KEY_DOWN:
			world.player_step(0, 1)
		KEY_A, KEY_LEFT:
			world.player_step(-1, 0)
		KEY_D, KEY_RIGHT:
			world.player_step(1, 0)
		KEY_I:
			inventory_open = true
		KEY_COMMA:
			world.player_loot()
		KEY_E:
			world.player_examine()
		KEY_PERIOD, KEY_5, KEY_SPACE:
			world.player_wait()
		KEY_F5:
			_save()
		KEY_F9:
			_load()
		KEY_R:
			world = World.new(item_data, monster_data)
			_visual.clear()
	_after_action()


func _is_move_key(key: int) -> bool:
	return key in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]


func _handle_inventory_key(key: int) -> void:
	if key == KEY_I or key == KEY_ESCAPE:
		inventory_open = false
		return
	if key < KEY_A or key > KEY_Z:
		return
	var index: int = key - KEY_A
	var items := world.player.inventory
	if index < 0 or index >= items.size():
		return
	world.player_use(items[index])


func _after_action() -> void:
	world.settle()
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
	world.log_message("已读档。")
