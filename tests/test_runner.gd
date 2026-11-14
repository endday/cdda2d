extends Node
## 无头测试入口。全部通过退出码 0，有失败为 1。
## 运行：Godot_v4.6-stable_win64_console.exe --headless --path . res://tests/test_runner.tscn

const SUITES: Array = [
	preload("res://tests/test_world.gd"),
	preload("res://tests/test_actions.gd"),
	preload("res://tests/test_combat.gd"),
	preload("res://tests/test_content.gd"),
	preload("res://tests/test_objective.gd"),
]


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var failures: Array[String] = []
	var checks: int = 0

	for suite_script: GDScript in SUITES:
		var suite: RefCounted = suite_script.new()
		failures.append_array(suite.run())
		checks += suite.check_count()
		print("[%s] %d 项检查" % [suite.suite_title(), suite.check_count()])

	print("")
	if failures.is_empty():
		print("全部通过：%d 项检查" % checks)
		get_tree().quit(0)
		return

	print("失败 %d 项（共 %d 项检查）：" % [failures.size(), checks])
	for failure: String in failures:
		print("  FAIL  %s" % failure)
	get_tree().quit(1)
