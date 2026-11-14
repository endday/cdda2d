extends RefCounted
## 字体覆盖测试：Web 端没有系统字体兜底，自带的中文字体子集必须盖住所有用到的字。

const MAX_REPORTED_FAILURES := 20
const FONT_PATH := "res://content/fonts/ui.otf"

var _failures: Array[String] = []
var _checks: int = 0


func suite_title() -> String:
	return "Font"


func check_count() -> int:
	return _checks


func run() -> Array[String]:
	_failures.clear()
	_checks = 0

	test_subset_covers_sources()

	return _failures


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func test_subset_covers_sources() -> void:
	var resource: Resource = load(FONT_PATH)
	if resource is not FontFile:
		_expect(false, "载入不到 %s —— 中文会变成方块" % FONT_PATH)
		return
	var font: FontFile = resource
	_expect(font.has_char("你".unicode_at(0)), "字体应该至少有一个中文字形")

	var missing: Dictionary = {}
	var files: Array[String] = []
	_walk("res://src", files)
	_walk("res://scenes", files)
	_walk("res://content", files)
	_expect(files.size() > 10, "应该扫到源码文件，实际 %d 个" % files.size())

	for path: String in files:
		var text := FileAccess.get_file_as_string(path)
		for i: int in text.length():
			var code := text.unicode_at(i)
			if code < 0x80:
				continue
			if not font.has_char(code):
				missing[code] = path
	if missing.is_empty():
		return
	var samples: Array[String] = []
	for code: int in missing.keys():
		samples.append("%s(%s)" % [char(code), missing[code]])
		if samples.size() >= 8:
			break
	_expect(false, "字体缺 %d 个字符，例如 %s —— 改完文案要跑 tools/build_font.py"
		% [missing.size(), ", ".join(samples)])


func _walk(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := path.path_join(name)
			if dir.current_is_dir():
				_walk(full, out)
			elif name.ends_with(".gd") or name.ends_with(".json") or name.ends_with(".tscn"):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()
