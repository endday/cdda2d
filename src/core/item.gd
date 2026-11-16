class_name Item
extends RefCounted
## 物品实例。对应 CDDA 的 `item`：原型 id + 这一件自己的状态。
##
## 原型（名字/重量/伤害/use_methods）在 content/items.json，是共享数据；
## 实例只存会变的东西：剩余次数、开关状态、耐久。
## 新增物品 = 往 JSON 加一条，不动这里。

var type_id := ""
var charges := 0        # 充能/剩余次数（手电筒电池、弹药以后用）
var active := false     # 开着没有（手电筒、工具）
var damage := 0         # 耐久损伤，0 = 完好


func _init(id: String = "", count: int = 0) -> void:
	type_id = id
	charges = count


func prototype(item_db: Dictionary) -> Dictionary:
	return item_db.get(type_id, {})


func to_dict() -> Dictionary:
	return {"type_id": type_id, "charges": charges, "active": active, "damage": damage}


func from_dict(data: Dictionary) -> void:
	type_id = String(data.get("type_id", ""))
	charges = int(data.get("charges", 0))
	active = bool(data.get("active", false))
	damage = int(data.get("damage", 0))
