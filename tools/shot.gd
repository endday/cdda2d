extends SceneTree
## 截图工具：加载主场景、可选地摆个 pose、存 png。
##
## 用法：
##   Godot... --path . --script res://tools/shot.gd
##   Godot... --path . --script res://tools/shot.gd -- pos=7,6 act=e
## 参数：pos=x,y 把玩家放过去；act=w,a,s,d,e,1,2,3,space 依次执行。
## 不要加 --headless（headless 没有渲染器）。

const WARMUP_FRAMES := 6
const OUT_PATH := "res://build/shot.png"

var _frames := 0
var _main: Node


func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	if main_scene == null:
		push_error("main.tscn 载入失败")
		quit(1)
		return
	_main = main_scene.instantiate()
	root.add_child(_main)


func _apply_args() -> void:
	# 等主场景 _ready 跑完，world 才存在。
	var world: World = _main.world
	if world == null:
		return
	for arg: String in OS.get_cmdline_user_args():
		if arg == "deploy":
			_main.call("_deploy_raid")
		elif arg.begins_with("pos="):
			var parts: PackedStringArray = arg.substr(4).split(",")
			if parts.size() == 2:
				world.player.pos = Vector2i(int(parts[0]), int(parts[1]))
				world.refresh_view()
		elif arg.begins_with("give="):
			for item_id: String in arg.substr(5).split(","):
				world.player.take_item(Item.new(item_id))
		elif arg.begins_with("act="):
			for step: String in arg.substr(4).split(","):
				match step:
					"w": world.player_step(0, -1)
					"s": world.player_step(0, 1)
					"a": world.player_step(-1, 0)
					"d": world.player_step(1, 0)
					"e": world.player_examine()
					"comma": world.player_loot()
					"i": _main.inventory_open = not _main.inventory_open
					"space", ".": world.player_wait()
					"e_repair": world.player_repair()
				world.settle()
	if _main.has_method("refresh_ui"):
		_main.refresh_ui()
	_main.queue_redraw()


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_apply_args()
	if _frames < WARMUP_FRAMES:
		return false
	var image := root.get_viewport().get_texture().get_image()
	var err := image.save_png(OUT_PATH)
	if err != OK:
		push_error("截图保存失败：%s" % err)
		quit(1)
		return true
	print("截图已保存：%s" % OUT_PATH)
	quit(0)
	return true
