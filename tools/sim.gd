extends SceneTree
## 平衡用的模拟器：不画画面，按一个简单策略把一局打到底，打印结果。
##
## 策略：旁边有怪就打最弱的那只；没有怪就修电台；都不行就等。
## 用法：Godot... --headless --path . --script res://tools/sim.gd [-- --seed 7 --runs 20]

const MAX_TURNS := 240

var _seed := 7
var _runs := 1
var _verbose := false


func _initialize() -> void:
	_parse_args()
	var wins := 0
	var deaths := 0
	var turns: Array[int] = []
	for i: int in _runs:
		var result := _play(_seed + i)
		turns.append(int(result["turn"]))
		if bool(result["won"]):
			wins += 1
		if bool(result["dead"]):
			deaths += 1
		print("第 %d 局：%s，回合 %d，HP %d，杀 %d，剩 %d 只" % [
			i + 1, result["outcome"], result["turn"], result["hp"],
			result["kills"], result["monsters"]])
	turns.sort()
	var median: int = turns[turns.size() / 2] if not turns.is_empty() else 0
	print("---")
	print("%d 局：胜 %d，死 %d，中位回合 %d" % [_runs, wins, deaths, median])
	quit(0)


func _parse_args() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("seed="):
			_seed = int(arg.substr(5))
		elif arg.begins_with("runs="):
			_runs = int(arg.substr(5))
		elif arg == "verbose":
			_verbose = true


func _load(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("读不到 %s" % path)
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if typeof(parsed) == TYPE_ARRAY else []


func _play(seed_value: int) -> Dictionary:
	var items := ContentDB.index_by_id(_load("res://content/items.json"))
	var monsters := ContentDB.index_by_id(_load("res://content/monsters.json"))
	var world := World.new(items, monsters, seed_value)
	var player := world.player
	# 假设玩家已经搜到了零件和一把刀（模拟"正常开局"）。
	player.inventory.append("knife")
	for part: String in World.REPAIR_PARTS:
		player.inventory.append(part)
	player.pos = world.repair_site
	# 玩家进塔时会把门推开，门开着怪才进得来——不然这局是假的。
	world.open_door(Vector2i(37, 21))
	world.refresh_view()

	var kills := 0
	for i: int in MAX_TURNS:
		if world.won or world.dead:
			break
		var before := _alive_monsters(world)
		if _attack_anything_adjacent(world):
			pass
		elif not world.radio_fixed and world.activity.is_empty():
			if not world.player_repair():
				world.player_wait()
		else:
			world.player_wait()
		world.settle()
		kills += maxi(0, before - _alive_monsters(world))
		if _verbose:
			print("  回合 %2d  HP %3d  修理 %s  守 %d  最近怪 %d 格  活怪 %d" % [
				world.turn, player.hp, world.radio_fixed, world.defense_left,
				_nearest(world), _alive_monsters(world)])

	var outcome := "进行中"
	if world.won:
		outcome = "通关"
	elif world.dead:
		outcome = "死亡"
	return {
		"outcome": outcome,
		"turn": world.turn,
		"hp": player.hp,
		"kills": kills,
		"monsters": _alive_monsters(world),
		"won": world.won,
		"dead": world.dead,
	}


func _alive_monsters(world: World) -> int:
	var count := 0
	for actor: Actor in world.actors:
		if actor != world.player and actor.alive:
			count += 1
	return count


func _nearest(world: World) -> int:
	var best := 999
	for actor: Actor in world.actors:
		if actor == world.player or not actor.alive:
			continue
		var dist: int = absi(actor.pos.x - world.player.pos.x) + absi(actor.pos.y - world.player.pos.y)
		best = mini(best, dist)
	return best


func _attack_anything_adjacent(world: World) -> bool:
	var best: Actor = null
	for actor: Actor in world.actors:
		if actor == world.player or not actor.alive:
			continue
		if absi(actor.pos.x - world.player.pos.x) + absi(actor.pos.y - world.player.pos.y) == 1:
			if best == null or actor.hp < best.hp:
				best = actor
	if best == null:
		return false
	world.player.moves = 100
	return world.player_attack(best)
