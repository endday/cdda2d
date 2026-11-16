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

var iso_texture: Texture2D
var iso_cells: Dictionary = {}   # 名字 -> 图集里的序号
const ISO_NAMES := ["floor", "pavement", "wall", "rock", "door_closed", "door_open"]

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
		var target := _iso(actor.pos)
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
func _iso(cell: Vector2i) -> Vector2:
	return Vector2((cell.x - cell.y) * ISO_W / 2.0, (cell.x + cell.y) * ISO_H / 2.0)


func _map_bounds() -> Rect2:
	var left := _iso(Vector2i(0, H - 1)).x - ISO_W / 2.0
	var right := _iso(Vector2i(W - 1, 0)).x + ISO_W / 2.0
	var top := -WALL_H - ISO_H
	var bottom := _iso(Vector2i(W - 1, H - 1)).y + ISO_H * 1.5
	return Rect2(left, top, right - left, bottom - top)


func _actor_world_pos(actor: Actor) -> Vector2:
	return _visual.get(actor.id, _iso(actor.pos))


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
	for actor: Actor in world.actors:
		if actor.pos != cell or not actor.alive:
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
