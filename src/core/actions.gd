extends RefCounted
## 具体动作。每个只做一件事，费用写在自己身上（CDDA 也是动作自己带 moves 成本）。
## 用法：`world.perform(actor, Actions.Walk.new(1, 0))`。


## 走一格。撞到关着的门会先开门（不移动），下一格才能过去。
## 斜走按 √2 计价（CDDA 的 `move_cost * M_SQRT2`），而且不能从两个墙角之间穿过去。
class Walk extends Action:
	const MOVE_COST := 100
	const RUN_COST := 50
	const DIAGONAL_COST := 141    # int(100 * sqrt(2))
	const RUN_DIAGONAL_COST := 71

	var dx: int = 0
	var dy: int = 0

	func _init(step_x: int, step_y: int) -> void:
		id = "walk"
		label = "移动"
		dx = step_x
		dy = step_y
		cost = MOVE_COST if dx == 0 or dy == 0 else DIAGONAL_COST

	func can(actor: Variant, world: Variant) -> String:
		if actor.run_mode and actor.stamina < Actor.MIN_RUN_STAMINA:
			return "你喘得太厉害，暂时跑不动。"
		var target: Vector2i = actor.pos + Vector2i(dx, dy)
		if world.is_wall(target):
			return "前面是墙。"
		if world.is_closed_door(target) and not actor.can_open_doors:
			return "门关着。"
		if dx != 0 and dy != 0:
			# 两个正交邻格都堵住时不许斜穿——CDDA 的 diagonal 检查。
			var side_a: Vector2i = actor.pos + Vector2i(dx, 0)
			var side_b: Vector2i = actor.pos + Vector2i(0, dy)
			if world.is_blocked(side_a) and world.is_blocked(side_b):
				return "拐角过不去。"
		return ""

	func cost_for(actor: Variant) -> int:
		if not actor.run_mode:
			return cost
		return RUN_COST if dx == 0 or dy == 0 else RUN_DIAGONAL_COST

	func _stamina_cost(actor: Variant, world: Variant) -> int:
		var ratio := 10 if actor.run_mode else 1
		var amount := maxi(1, int(round(float(cost_for(actor) * ratio) / 100.0)))
		if actor.total_weight(world.item_db) > actor.max_weight:
			amount = maxi(amount, int(ceil(float(amount) * 1.5)))
		return amount

	func apply(actor: Variant, world: Variant) -> bool:
		var target: Vector2i = actor.pos + Vector2i(dx, dy)
		actor.burn_stamina(_stamina_cost(actor, world))
		if world.is_closed_door(target):
			world.open_door(target)
			world.log_message("%s推开门。" % _who(actor))
			return true
		actor.pos = target
		return true

	func _who(actor: Variant) -> String:
		return "你" if actor.is_player else ""


## 搜脚下的东西。
class Loot extends Action:
	func _init() -> void:
		id = "loot"
		label = "搜刮"
		cost = 50

	func can(actor: Variant, world: Variant) -> String:
		if world.items_at(actor.pos).is_empty():
			return "这里没有东西。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var taken: Array[String] = world.take_items_at(actor)
		if taken.is_empty():
			return false
		world.log_message("搜到：%s。" % ", ".join(taken))
		return true


## Move in continuous coordinates. Terrain collision uses map cells, and cost scales with distance.
class FreeMove extends Action:
	const WALK_COST_PER_TILE := 100
	const RUN_COST_PER_TILE := 50
	const INVALID_CELL := Vector2i(-1, -1)

	var direction := Vector2.ZERO
	var distance := 0.0
	var door_to_open := INVALID_CELL

	func _init(move_direction: Vector2, move_distance: float) -> void:
		id = "move"
		label = "移动"
		direction = move_direction.normalized()
		distance = maxf(0.0, move_distance)

	func can(actor: Variant, world: Variant) -> String:
		door_to_open = INVALID_CELL
		if direction.is_zero_approx() or distance <= 0.0:
			return "前面是墙。"
		if actor.run_mode and actor.stamina < Actor.MIN_RUN_STAMINA:
			return "你喘得太厉害，暂时跑不动。"
		var start: Vector2 = actor.free_pos
		var finish := start + direction * distance
		var previous_cell: Vector2i = world.cell_at(start)
		var samples := maxi(1, ceili(distance / 0.05))
		for index: int in range(1, samples + 1):
			var sample := start.lerp(finish, float(index) / samples)
			var cell: Vector2i = world.cell_at(sample)
			if cell == previous_cell:
				continue
			if world.is_wall(cell):
				return "前面是墙。"
			if world.is_closed_door(cell):
				if not actor.can_open_doors:
					return "门关着。"
				door_to_open = cell
				return ""
			var step := cell - previous_cell
			if absi(step.x) > 1 or absi(step.y) > 1:
				return "前面是墙。"
			if step.x != 0 and step.y != 0:
				var side_a := previous_cell + Vector2i(step.x, 0)
				var side_b := previous_cell + Vector2i(0, step.y)
				if world.is_blocked(side_a) and world.is_blocked(side_b):
					return "拐角过不去。"
			var occupant: Actor = world.actor_at(cell)
			if occupant != null and occupant != actor:
				return "前面是墙。"
			previous_cell = cell
		if world.actor_near(finish, 0.4, actor) != null:
			return "前面是墙。"
		return ""

	func cost_for(actor: Variant) -> int:
		if door_to_open != INVALID_CELL:
			return RUN_COST_PER_TILE if actor.run_mode else WALK_COST_PER_TILE
		var rate := RUN_COST_PER_TILE if actor.run_mode else WALK_COST_PER_TILE
		return maxi(1, int(round(distance * rate)))

	func _stamina_cost(actor: Variant, world: Variant) -> int:
		var stamina_per_tile := 5.0 if actor.run_mode else 1.0
		var distance_to_pay := 1.0 if door_to_open != INVALID_CELL else distance
		var raw_amount: float = distance_to_pay * stamina_per_tile + actor.stamina_move_remainder
		var amount := floori(raw_amount)
		actor.stamina_move_remainder = raw_amount - amount
		if actor.total_weight(world.item_db) > actor.max_weight:
			amount = int(ceil(float(amount) * 1.5))
		return amount

	func apply(actor: Variant, world: Variant) -> bool:
		actor.burn_stamina(_stamina_cost(actor, world))
		if door_to_open != INVALID_CELL:
			world.open_door(door_to_open)
			world.log_message("%s推开门。" % ("你" if actor.is_player else ""))
			return true
		actor.free_pos += direction * distance
		return true


class SearchContainer extends Action:
	var container: Dictionary

	func _init(target: Dictionary) -> void:
		id = "search_container"
		label = "搜索"
		cost = 100
		container = target

	func can(_actor: Variant, _world: Variant) -> String:
		if container.is_empty():
			return "这里没有可搜索的容器。"
		if bool(container.get("searched", false)):
			return "已经搜过了。"
		return ""

	func apply(_actor: Variant, world: Variant) -> bool:
		return world.search_container(container)


## 用一件背包里的东西。走 ItemUse 注册表——加新物品不用改这里。
class UseItem extends Action:
	var item: Item
	var method: Dictionary

	func _init(target: Item, selected_method: Dictionary = {}) -> void:
		id = "use"
		label = "使用"
		cost = 50
		item = target
		method = selected_method.duplicate(true)

	func can(actor: Variant, world: Variant) -> String:
		if item == null or not actor.inventory.has(item):
			return "背包里没有这件东西。"
		if method.is_empty():
			return ItemUse.can_use(actor, world, item)
		return ItemUse.can_use_method(actor, world, item, method)

	func apply(actor: Variant, world: Variant) -> bool:
		var result: Dictionary = ItemUse.use(actor, world, item) if method.is_empty() else ItemUse.use_method(actor, world, item, method)
		if not bool(result.get("ok", false)):
			world.log_message(String(result.get("message", "用不了。")))
			return false
		var message := String(result.get("message", ""))
		if not message.is_empty():
			world.log_message(message)
		if bool(result.get("consume", false)):
			actor.remove_item(item)
		return true


class Wield extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "wield"
		label = "手持"
		cost = 100
		item = target

	func can(actor: Variant, _world: Variant) -> String:
		if item == null or not actor.inventory.has(item):
			return "背包里没有这件东西。"
		if not actor.can_wield_main(item, _world.item_db):
			return "这件东西不能手持战斗。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		actor.wield_item(item)
		world.log_message("你手持了%s。" % world.item_name(item.type_id))
		return true


class Unwield extends Action:
	func _init() -> void:
		id = "unwield"
		label = "卸下手持物"
		cost = 100

	func can(actor: Variant, world: Variant) -> String:
		if actor.wielded == null:
			return "你主手没有东西。"
		var item: Item = actor.wielded
		if actor.total_volume(world.item_db) + int(item.prototype(world.item_db).get("volume", 0)) > actor.max_volume(world.item_db):
			return "背包空间不足，先腾出空间再收起主手物品。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var name: String = world.item_name(actor.wielded.type_id)
		actor.unwield_item()
		world.log_message("你放下了%s。" % name)
		return true


class HoldOffhand extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "hold_offhand"
		label = "放入副手"
		cost = 100
		item = target

	func can(actor: Variant, world: Variant) -> String:
		if not actor.can_hold_offhand(item, world.item_db):
			return "这件东西不能放在副手。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		if not actor.hold_offhand(item, world.item_db):
			return false
		world.log_message("你把%s拿在副手。" % world.item_name(item.type_id))
		return true


class UnholdOffhand extends Action:
	func _init() -> void:
		id = "unhold_offhand"
		label = "腾出副手"
		cost = 100

	func can(actor: Variant, world: Variant) -> String:
		if actor.offhand == null:
			return "副手是空的。"
		var item: Item = actor.offhand
		if actor.total_volume(world.item_db) + int(item.prototype(world.item_db).get("volume", 0)) > actor.max_volume(world.item_db):
			return "背包空间不足，先腾出空间再收起副手物品。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var name: String = world.item_name(actor.offhand.type_id)
		actor.unhold_offhand()
		world.log_message("你腾出了副手（%s）。" % name)
		return true


class Wear extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "wear"
		label = "穿戴"
		cost = 100
		item = target

	func can(actor: Variant, world: Variant) -> String:
		if item == null or not actor.inventory.has(item):
			return "背包里没有这件东西。"
		if actor.worn.has(item):
			return "已经穿着了。"
		var prototype := item.prototype(world.item_db)
		var flags: Array = prototype.get("flags", [])
		if not prototype.has("armor") and not prototype.has("capacity_volume") and not ("WEARABLE" in flags):
			return "这件东西不能穿戴。"
		if actor.equipment_slot(prototype).is_empty():
			return "这件东西没有可穿戴的装备位。"
		if not actor.can_wear(item, world.item_db):
			return "当前背包空间不够容纳换下的装备。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		actor.wear_item(item, world.item_db)
		world.log_message("你穿上了%s。" % world.item_name(item.type_id))
		return true


class Unwear extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "unwear"
		label = "脱下"
		cost = 100
		item = target

	func can(actor: Variant, world: Variant) -> String:
		if item == null or not actor.worn.has(item):
			return "这件东西没有穿着。"
		var prototype := item.prototype(world.item_db)
		var capacity_after: int = actor.max_volume(world.item_db) - int(prototype.get("capacity_volume", 0))
		if actor.total_volume(world.item_db) + int(prototype.get("volume", 0)) > capacity_after:
			return "背包空间不足，先腾出空间再脱下这件装备。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		actor.remove_worn(item)
		world.log_message("你脱下了%s。" % world.item_name(item.type_id))
		return true


class Drop extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "drop"
		label = "丢弃"
		cost = 50
		item = target

	func can(actor: Variant, _world: Variant) -> String:
		return "背包里没有这件东西。" if item == null or not actor.inventory.has(item) else ""

	func apply(actor: Variant, world: Variant) -> bool:
		actor.remove_item(item)
		world.drop_item(actor, item)
		world.log_message("你丢下了%s。" % world.item_name(item.type_id))
		return true


class Disassemble extends Action:
	var item: Item

	func _init(target: Item) -> void:
		id = "disassemble"
		label = "拆解"
		cost = 100
		item = target

	func can(actor: Variant, world: Variant) -> String:
		if item == null or not actor.inventory.has(item):
			return "背包里没有这件东西。"
		if item.prototype(world.item_db).get("disassemble", []).is_empty():
			return "这件东西不能拆解。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var prototype := item.prototype(world.item_db)
		actor.remove_item(item)
		var names: Array[String] = []
		for entry: Variant in prototype.get("disassemble", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var result: Dictionary = entry
			var id := String(result.get("id", ""))
			var count := maxi(1, int(result.get("count", 1)))
			if id.is_empty() or not world.item_db.has(id):
				continue
			for _i: int in range(count):
				actor.take_item(Item.new(id))
			names.append("%s×%d" % [world.item_name(id), count])
		world.log_message("你拆解了%s，得到%s。" % [world.item_name(item.type_id), "、".join(names)])
		return true


## 等。CDDA 里空格就是这个动作，不是“结束回合”的开关；花掉一整个回合的 moves。
## 剩的 moves 不够 100 时，有多少花多少，照样把回合让出去。
class Wait extends Action:
	func _init() -> void:
		id = "wait"
		label = "等待"
		cost = 100

	func cost_for(actor: Variant) -> int:
		# 等：有多少花多少，但至少花 1，别让停在 0 上不推进。
		return maxi(1, mini(cost, actor.moves))

	func apply(_actor: Variant, _world: Variant) -> bool:
		return true


## 近战。相邻才能打，结算交给 Combat（命中/伤害/护甲）。
class Attack extends Action:
	var target: Actor

	func _init(who: Actor) -> void:
		id = "attack"
		label = "攻击"
		cost = 100
		target = who

	func can(actor: Variant, _world: Variant) -> String:
		if target == null or not target.alive:
			return "那里没有活物。"
		if _distance(actor.cell_pos, target.cell_pos) > 1:
			return "太远了，得先靠近。"
		return ""

	func apply(actor: Variant, world: Variant) -> bool:
		var result: Dictionary = Combat.resolve(actor, target, world.item_db, world.rng)
		var who := "你" if actor.is_player else String(actor.name)
		var victim := "你" if target.is_player else String(target.name)
		if not bool(result["hit"]):
			world.log_message("%s打空了。" % who)
			return true
		var amount: int = int(result["damage"])
		target.take_damage(amount)
		world.log_message("%s打中%s，%d 点伤害。" % [who, victim, amount])
		if not target.alive:
			world.log_message("%s倒下了。" % victim)
		return true

	func _distance(a: Vector2i, b: Vector2i) -> int:
		return absi(a.x - b.x) + absi(a.y - b.y)
