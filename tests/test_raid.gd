extends RefCounted
## 单人搜打撤闭环的测试。

const MAX_REPORTED_FAILURES := 20
const MainScene := preload("res://scenes/main.gd")

var _failures: Array[String] = []
var _checks := 0


func suite_title() -> String:
	return "Raid"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0
	test_container_search()
	test_extract_returns_carried_items()
	test_death_discards_carried_items()
	test_raid_timer_expiry_fails_run()
	test_mouse_path_finds_route_to_search_point()
	test_raid_state_save_roundtrip()
	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _db() -> Dictionary:
	return {
		"water": {"id": "water", "name": "水", "weight": 0.5, "volume": 500},
		"canned_food": {"id": "canned_food", "name": "罐头", "weight": 0.4, "volume": 400},
		"bandage": {"id": "bandage", "name": "绷带", "weight": 0.1, "volume": 100},
	}


func _world() -> World:
	return World.new(_db(), {}, 77)


func test_container_search() -> void:
	var world := _world()
	var container := world.containers[0]
	world.player.pos = container["pos"]
	world.player.moves = 100
	_expect(world.player_search_container(container), "容器应该可以搜索")
	_expect(bool(container["searched"]), "搜索后容器应该标记为已搜")
	_expect(world.player.inventory.size() == 3, "在容器位置搜索后应该自动收取可携带战利品")
	_expect(not world.player_search_container(container), "已经搜索的容器不能重复获得战利品")


func test_extract_returns_carried_items() -> void:
	var world := _world()
	world.player.pos = world.extract_site
	world.player.moves = 100
	world.player.take_item(Item.new("water"))
	_expect(world.player_extract(), "撤离点应该能完成撤离")
	_expect(world.extracted and world.won, "成功撤离应该结束本局")
	_expect(world.stash == ["water"], "撤离应该把携带物品带回仓库")


func test_death_discards_carried_items() -> void:
	var world := _world()
	world.player.take_item(Item.new("water"))
	world.player.take_damage(999)
	world.advance_turn()
	_expect(world.dead, "致命伤害后玩家应该死亡")
	_expect(world.player.inventory.is_empty(), "死亡后本局携带物应该遗失")
	_expect(world.stash.is_empty(), "死亡不应该把物品放进仓库")
	_expect(world.death_summary.get("loot", []).size() == 1, "死亡结算应该记录遗失物品")


func test_raid_timer_expiry_fails_run() -> void:
	var world := _world()
	world.player.take_item(Item.new("water"))
	world.raid_turns_left = 1
	world.advance_turn()
	_expect(world.raid_failed, "撤离计时归零应该判定本局失败")
	_expect(world.player.inventory.is_empty(), "错过撤离窗口后携带物资应该遗失")
	_expect(not world.player_extract(), "撤离窗口关闭后不能撤离")


func test_mouse_path_finds_route_to_search_point() -> void:
	var world := _world()
	var scene := MainScene.new()
	scene.world = world
	var start := world.player.pos
	var destination: Vector2i = world.containers[0]["pos"]
	var step: Vector2i = scene._next_path_step(start, destination)
	_expect(step != Vector2i.ZERO, "鼠标寻路应该能找到住宅容器的入口路线")
	_expect(not world.is_wall(start + step), "鼠标寻路第一步不能穿墙")
	scene.free()


func test_raid_state_save_roundtrip() -> void:
	var world := _world()
	world.containers[0]["searched"] = true
	world.raid_turns_left = 93
	world.stash.append("water")
	var restored := _world()
	_expect(restored.from_dict(world.to_dict()), "本局和仓库状态应该可以读档")
	_expect(restored.raid_turns_left == 93, "读档后撤离计时应该保留")
	_expect(bool(restored.containers[0]["searched"]), "读档后容器搜索状态应该保留")
	_expect(restored.stash == ["water"], "读档后仓库物品应该保留")
