class_name ItemUse
extends RefCounted
## 物品动词注册表 —— CDDA `iuse_actor` 的微缩版。
##
## CDDA 里每件物品的 `use_methods` 是一串 `{type: "consume_drug", ...}`，
## 引擎按 type 找到对应的 `iuse_actor` 子类来执行（src/iuse_actor.cpp）。
## 我们照这个来：物品 JSON 只写 `{"type": "...", 参数}`，代码里注册同名的处理器。
##
## 加一件新物品 = 往 items.json 加一条，挑一个已有的 type。
## 加一种新玩法 = ItemUse.register("<type>", can, use)，不用改 World / UI。
##
## 处理器返回 {"ok", "message", "consume", "replace"}：
##   consume  → 用掉一个
##   replace  → 变成另一个原型（手电筒开/关这种）

static var _handlers: Dictionary = {}
static var _builtins: Builtins = null   # 必须留着引用，否则 Callable 会指向已释放的实例


## 注册一个物品动词。can/use 都是 Callable(actor, world, item, method) -> Variant。
static func register(type: String, can: Callable, use: Callable) -> void:
	_handlers[type] = {"can": can, "use": use}


static func has(type: String) -> bool:
	_ensure_builtins()
	return _handlers.has(type)


static func known_types() -> Array[String]:
	_ensure_builtins()
	var out: Array[String] = []
	for key: String in _handlers.keys():
		out.append(key)
	out.sort()
	return out


## 这件物品能不能用：返回空串表示能，否则是给玩家看的原因。
## 一件东西可能有多个 use_methods，取第一个能用的。
static func can_use(actor: Actor, world: Variant, item: Item) -> String:
	_ensure_builtins()
	var method := _first_usable(actor, world, item)
	if method.is_empty():
		return "%s 现在用不了。" % world.item_name(item.type_id)
	var handler: Dictionary = _handlers[String(method["type"])]
	return String(handler["can"].call(actor, world, item, method))


static func use(actor: Actor, world: Variant, item: Item) -> Dictionary:
	_ensure_builtins()
	var method := _first_usable(actor, world, item)
	if method.is_empty():
		return {"ok": false, "message": "用不了。", "consume": false, "replace": ""}
	var handler: Dictionary = _handlers[String(method["type"])]
	return Dictionary(handler["use"].call(actor, world, item, method))


static func can_use_method(actor: Actor, world: Variant, item: Item, method: Dictionary) -> String:
	_ensure_builtins()
	var type := String(method.get("type", ""))
	if not _handlers.has(type):
		return "这个动作没有处理器。"
	var handler: Dictionary = _handlers[type]
	return String(handler["can"].call(actor, world, item, method))


static func use_method(actor: Actor, world: Variant, item: Item, method: Dictionary) -> Dictionary:
	_ensure_builtins()
	var type := String(method.get("type", ""))
	if not _handlers.has(type):
		return {"ok": false, "message": "这个动作没有处理器。", "consume": false, "replace": ""}
	var handler: Dictionary = _handlers[type]
	return Dictionary(handler["use"].call(actor, world, item, method))


static func _first_usable(actor: Actor, world: Variant, item: Item) -> Dictionary:
	var data: Dictionary = world.item_db.get(item.type_id, {})
	for entry: Variant in data.get("use_methods", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var method: Dictionary = entry
		var type := String(method.get("type", ""))
		if not _handlers.has(type):
			continue
		var handler: Dictionary = _handlers[type]
		if String(handler["can"].call(actor, world, item, method)) == "":
			return method
	return {}


## 清空注册表（测试和热重载用）。下次调用会自动重新注册内置动词。
static func reset() -> void:
	_handlers.clear()
	_builtins = null


static func _ensure_builtins() -> void:
	if not _handlers.is_empty():
		return
	_builtins = Builtins.new()
	register("consume", _builtins.consume_can, _builtins.consume_use)
	register("heal", _builtins.heal_can, _builtins.heal_use)
	register("transform", _builtins.transform_can, _builtins.transform_use)


## 内置处理器。写成一个类，方便把方法当 Callable 注册。
class Builtins extends RefCounted:
	func consume_can(actor: Actor, _world: Variant, _item: Item, method: Dictionary) -> String:
		var quench := int(method.get("quench", 0))
		var calories := int(method.get("calories", 0))
		if quench <= 0 and calories <= 0:
			return "这个东西不能吃也不能喝。"
		if actor.thirst >= 100 and quench > 0 and calories <= 0:
			return "%s 现在喝不下。" % _name(method)
		if actor.hunger >= 100 and calories > 0 and quench <= 0:
			return "%s 现在吃不下。" % _name(method)
		return ""

	func consume_use(actor: Actor, _world: Variant, _item: Item, method: Dictionary) -> Dictionary:
		var quench := int(method.get("quench", 0))
		var calories := int(method.get("calories", 0))
		actor.thirst = mini(100, actor.thirst + quench)
		actor.hunger = mini(100, actor.hunger + calories)
		var verb := "喝掉" if quench > 0 else "吃掉"
		return {
			"ok": true,
			"message": "你%s%s。" % [verb, _name(method)],
			"consume": true,
			"replace": "",
		}

	func heal_can(actor: Actor, _world: Variant, _item: Item, method: Dictionary) -> String:
		var heal := int(method.get("heal", 0))
		var cure := int(method.get("cure", 0))
		if heal <= 0 and cure <= 0:
			return "这个不能治伤。"
		if actor.hp >= actor.hp_max and actor.infection <= 0:
			return "你现在不需要这个。"
		return ""

	func heal_use(actor: Actor, _world: Variant, _item: Item, method: Dictionary) -> Dictionary:
		var healed := int(method.get("heal", 0))
		var cured := mini(actor.infection, int(method.get("cure", 0)))
		actor.heal(healed)
		actor.infection = maxi(0, actor.infection - cured)
		return {
			"ok": true,
			"message": "你用了%s。" % _name(method),
			"consume": true,
			"replace": "",
		}

	func transform_can(_actor: Actor, world: Variant, _item: Item, method: Dictionary) -> String:
		var to := String(method.get("to", ""))
		if to.is_empty():
			return "这个道具没配目标状态。"
		if not world.item_db.has(to):
			return "目标状态不存在：%s。" % to
		return ""

	func transform_use(_actor: Actor, world: Variant, item: Item, method: Dictionary) -> Dictionary:
		var to := String(method["to"])
		item.type_id = to
		item.active = true
		return {
			"ok": true,
			"message": "你用了一下%s。" % _name(method),
			"consume": false,
			"replace": to,
		}

	func _name(method: Dictionary) -> String:
		return String(method.get("msg", "东西"))
