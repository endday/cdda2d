extends RefCounted
## World 灰盒的回归测试：地图/门/移动/搜刮/使用/需求/存档。

const MAX_REPORTED_FAILURES := 20

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "World"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_map_shape()
	test_wall_blocks()
	test_move_costs_moves()
	test_door_blocks_until_opened()
	test_loot_and_use()
	test_needs_tick()
	test_save_roundtrip()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _db() -> Dictionary:
	return {
		"water": {"id": "water", "name": "瓶装水", "kind": "water", "hydration": 40},
		"canned_food": {"id": "canned_food", "name": "罐头", "kind": "food", "nutrition": 35},
		"bandage": {"id": "bandage", "name": "绷带", "kind": "med", "heal": 15},
	}


func test_map_shape() -> void:
	var world := World.new(_db())
	var row: PackedInt32Array = world.map[0]
	_expect(world.map.size() == World.H, "地图高度应为 %d" % World.H)
	_expect(row.size() == World.W, "地图宽度应为 %d" % World.W)
	_expect(world.player.pos == Vector2i(24, 13), "玩家应出生在 (24,13)，实际 %s" % world.player.pos)
	_expect(world.is_wall(Vector2i(0, 0)), "外墙应是墙")
	_expect(not world.is_blocked(Vector2i(24, 13)), "出生点应可走")


func test_wall_blocks() -> void:
	var world := World.new(_db())
	world.player.pos = Vector2i(1, 1)
	world.player.moves = Actor.BASE_SPEED
	_expect(not world.player_move(-1, 0), "撞墙应失败")
	_expect(world.player.pos == Vector2i(1, 1), "撞墙后位置不变")
	_expect(world.player.moves == Actor.BASE_SPEED, "撞墙不该扣 moves")


func test_move_costs_moves() -> void:
	var world := World.new(_db())
	world.player.pos = Vector2i(24, 13)
	world.player.moves = Actor.BASE_SPEED
	_expect(world.player_move(1, 0), "向右走应成功")
	_expect(world.player.moves == 0, "走一格应花 100 moves，实际 %d" % world.player.moves)
	_expect(not world.player_move(1, 0), "moves 用尽后不能再走")
	world.settle()
	_expect(world.player.moves == Actor.BASE_SPEED, "settle 后应拿到新回合的 moves，实际 %d" % world.player.moves)
	_expect(world.turn == 2, "settle 应推进一回合，实际 %d" % world.turn)


func test_door_blocks_until_opened() -> void:
	var world := World.new(_db())
	var door := Vector2i(8, 11)
	world.player.pos = Vector2i(8, 12)
	world.player.moves = Actor.BASE_SPEED * 2
	_expect(world.is_closed_door(door), "门初始应是关着的")
	_expect(world.is_blocked(door), "关着的门应挡路")
	_expect(world.player_move(0, -1), "撞门应能推开")
	_expect(world.player.pos == Vector2i(8, 12), "推门这一下不该走过去")
	_expect(not world.is_closed_door(door), "推开后门应是开的")
	_expect(world.player_move(0, -1), "门开之后应该能走过去")
	_expect(world.player.pos == door, "应该站到门那格，实际 %s" % world.player.pos)


func test_loot_and_use() -> void:
	var world := World.new(_db())
	world.player.pos = Vector2i(6, 6)
	world.player.moves = Actor.BASE_SPEED
	_expect(world.player_loot(), "水应该在 (6,6)")
	_expect(world.player.inventory.has("water"), "背包里应有水")
	world.player.thirst = 10
	_expect(world.player_use("water"), "应该能喝水")
	_expect(world.player.thirst == 50, "水应回 40 口渴，实际 %d" % world.player.thirst)


func test_needs_tick() -> void:
	var world := World.new(_db())
	world.player.hunger = 1
	world.player.thirst = 1
	world.advance_turn()
	_expect(world.player.hunger == 0, "饥饿应降到 0，实际 %d" % world.player.hunger)
	_expect(world.player.thirst == 0, "口渴应降到 0，实际 %d" % world.player.thirst)
	_expect(world.player.hp < 100, "饥饿/口渴见底应掉血，实际 %d" % world.player.hp)


func test_save_roundtrip() -> void:
	var world := World.new(_db())
	world.player.pos = Vector2i(6, 6)
	world.player_loot()
	world.player.thirst = 42
	world.open_door(Vector2i(8, 11))
	var data := world.to_dict()
	_expect(data.has("version"), "存档应带版本号")

	var restored := World.new(_db())
	_expect(restored.from_dict(data), "同版本存档应能读")
	_expect(restored.player.pos == Vector2i(6, 6), "读档后位置应一致")
	_expect(restored.player.thirst == 42, "读档后口渴应一致")
	_expect(restored.player.inventory.has("water"), "读档后背包应一致")
	_expect(not restored.is_closed_door(Vector2i(8, 11)), "读档后开着的门应还是开的")

	var bad := World.new(_db())
	_expect(not bad.from_dict({"version": 1}), "旧版本存档应被拒绝")
