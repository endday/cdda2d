# 字体

`ui.otf` 是 **Noto Sans SC Regular** 的子集，只保留本项目界面/内容里出现过的字
（约 690 个字符，259 KB），用 `tools/build_font.py` 生成。

- 上游：<https://github.com/notofonts/noto-cjk>（`Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf`）
- 许可证：**SIL Open Font License 1.1**，见 `OFL.txt`
- 署名：Noto Sans CJK, © Google / Adobe, SIL OFL 1.1

## 为什么必须自带

Godot 默认字体没有中日韩字形。桌面端靠系统字体兜底，Web 端没有系统字体，
所有中文会变成方块。加了这份子集之后，浏览器里才显示正常。

## 改了文案之后

```
python tools/build_font.py
```

`tests/test_font.gd` 会扫描 `src/`、`scenes/`、`content/` 里所有非 ASCII 字符，
字体缺任何一个都会让测试变红——所以忘了重跑脚本会被抓出来。
