extends RefCounted
## 电台目标的测试：零件、修理活动、守塔、通关。

const MAX_REPORTED_FAILURES := 20

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Objective"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_repair_needs_tower_and_parts()
	test_repair_starts_activity()
	test_activity_completes_and_starts_defense()
	test_defense_ends_in_win()
	test_moving_cancels_repair()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


## 没有怪物库 → 世界里不会刷怪，专测目标逻辑。
func _world() -> World:
	return World.new({}, {}, 4242)


func _give_parts(world: World) -> void:
	for part: String in World.REPAIR_PARTS:
		world.player.take_item(Item.new(part))


func test_repair_needs_tower_and_parts() -> void:
	var world := _world()
	_expect(not world.player_repair(), "不在塔上不能修")
	world.player.pos = world.repair_site
	_expect(not world.player_repair(), "没零件不能修")
	_expect(world.activity.is_empty(), "失败不该开始活动")
	world.player.take_item(Item.new("radio_part"))
	_expect(not world.player_repair(), "只带一件零件不能修")
	_expect(world.player.has_item("radio_part"), "失败不该吃掉零件")


func test_repair_starts_activity() -> void:
	var world := _world()
	world.player.pos = world.repair_site
	_give_parts(world)
	_expect(world.player_repair(), "带齐零件在塔上应该能开始修")
	_expect(int(world.activity.get("turns_left", 0)) == World.REPAIR_TURNS,
		"活动应该剩 %d 回合，实际 %s" % [World.REPAIR_TURNS, world.activity])
	for part: String in World.REPAIR_PARTS:
		_expect(not world.player.has_item(part), "%s 应该被消耗掉" % part)


func test_activity_completes_and_starts_defense() -> void:
	var world := _world()
	world.player.pos = world.repair_site
	_give_parts(world)
	world.player_repair()
	for i: int in World.REPAIR_TURNS:
		world.advance_turn()
	_expect(world.radio_fixed, "修完应该 radio_fixed")
	_expect(world.activity.is_empty(), "修完活动应该清空")
	_expect(world.defense_left == World.DEFENSE_TURNS,
		"应该开始守 %d 回合，实际 %d" % [World.DEFENSE_TURNS, world.defense_left])


func test_defense_ends_in_win() -> void:
	var world := _world()
	world.player.pos = world.repair_site
	_give_parts(world)
	world.player_repair()
	for i: int in World.REPAIR_TURNS + World.DEFENSE_TURNS:
		world.advance_turn()
	_expect(not world.dead, "没有怪的情况下不该死")
	_expect(world.won, "守完 %d 回合应该通关，现在 defense_left=%d"
		% [World.DEFENSE_TURNS, world.defense_left])


func test_moving_cancels_repair() -> void:
	var world := _world()
	world.player.pos = world.repair_site
	_give_parts(world)
	world.player_repair()
	world.player.moves = 200
	world.player_move(1, 0)
	_expect(world.activity.is_empty(), "修理中走一步应该打断")
	_expect(not world.radio_fixed, "打断后不该算修好")
