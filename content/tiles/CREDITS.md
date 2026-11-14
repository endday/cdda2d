# 素材来源

`tileset.png` / `actors.png` 里的像素来自 **Cataclysm: Dark Days Ahead** 的
**Ultimate Cataclysm (UltiCa)** tileset，由 CDDA 社区志愿者创作。

- 来源：<https://github.com/Cataclysm-DDA/CDDA-Tilesets>（0.H 版本的成品 tileset）
- 原图：`gfx/UltimateCataclysm/{small,normal,human_body_plus}.png` + `tile_config.json`
- 本项目只**裁切**了 26 个图：4 种地形各 4 个 multitile 变体（实际只用第 0 张）、
  2 张开/关门、20 张物品，外加 2 帧角色（32×48）。没有改画。
- 裁切脚本：`tools/extract_tiles.py`（可重跑，换版本只改 `SHEET_DIMS`）。

## 许可证

CC BY-SA 3.0 Unported（全文见 `CDDA-LICENSE.txt`）。
这意味着：这些贴图可以免费用、改、再分发，但**必须署名**，
并且基于它改出来的素材要以同样的 CC BY-SA 3.0 释出。

署名建议（放到游戏内或 README）：

> Tiles by the Cataclysm: Dark Days Ahead community (UltiCa), CC BY-SA 3.0.

如果以后要商用或不接受 ShareAlike，就得换成 CC0/CC BY 的素材
（比如 Kenney 的 1-Bit Pack），或者自己画。
