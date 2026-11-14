"""给 Web 端打包一份中文字体子集。

Godot 默认字体没有中日韩字形，桌面端靠系统字体兜底，Web 端没有兜底 → 全是方块。
所以把 Noto Sans SC 裁成「本项目实际用到的字」，放进 content/fonts/ui.otf。

源字体（不进仓库，放在 _ref/fonts/）：
    https://github.com/notofonts/noto-cjk  Sans/OTF/SimplifiedChinese/NotoSansCJKsc-Regular.otf
许可证：SIL Open Font License 1.1（可再分发，保留署名，见 content/fonts/CREDITS.md）

用法：python tools/build_font.py
改了界面文案/内容 JSON 之后要重跑；tests/test_font.gd 会检查有没有漏字。
"""

import os
import sys

from fontTools import subset

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SOURCE_FONT = os.path.join(PROJECT, "..", "_ref", "fonts", "NotoSansSC-Regular.otf")
OUT_DIR = os.path.join(PROJECT, "content", "fonts")
OUT_FONT = os.path.join(OUT_DIR, "ui.otf")

# 界面里一定会用到的符号：数字/英文字母/常用中英标点。
ALWAYS = (
    "".join(chr(c) for c in range(0x20, 0x7F))
    + "　，。、：；！？（）【】「」《》…—·～＋－×÷°"
    + "←↑→↓"
)

SCAN_DIRS = ["src", "scenes", "content"]
SCAN_EXTS = {".gd", ".json", ".tscn"}


def collect_text() -> str:
    chars = set(ALWAYS)
    for folder in SCAN_DIRS:
        root = os.path.join(PROJECT, folder)
        for base, _dirs, files in os.walk(root):
            for name in files:
                if os.path.splitext(name)[1] not in SCAN_EXTS:
                    continue
                path = os.path.join(base, name)
                with open(path, encoding="utf-8", errors="ignore") as fh:
                    chars.update(fh.read())
    return "".join(sorted(chars))


def main() -> int:
    if not os.path.exists(SOURCE_FONT):
        print("找不到源字体：%s" % SOURCE_FONT)
        return 1
    text = collect_text()
    os.makedirs(OUT_DIR, exist_ok=True)

    options = subset.Options()
    options.hinting = False
    options.desubroutinize = True
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.notdef_outline = True
    options.glyph_names = False

    font = subset.load_font(SOURCE_FONT, options)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=text)
    subsetter.subset(font)
    subset.save_font(font, OUT_FONT, options)

    size_kb = os.path.getsize(OUT_FONT) / 1024
    print("字体子集：%d 个字符 -> %s（%.0f KB）" % (len(text), OUT_FONT, size_kb))
    return 0


if __name__ == "__main__":
    sys.exit(main())
