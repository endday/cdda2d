#!/usr/bin/env python3
"""Build CDDA2D for Web + Windows + Linux.

Usage:
    python tools/build_all.py
    python tools/build_all.py --only Web
    python tools/build_all.py --godot "D:/path/to/Godot_v4.6-stable_win64_console.exe"

Requires Godot 4.6 export templates:
    Editor > Manage Export Templates > Download and Install.
"""
from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_GODOT = r"D:\project\ai-project\Godot_v4.6-stable_win64_console.exe"
PRESETS = [
    ("Web", "build/web/index.html"),
    ("Windows", "build/windows/cdda2d.exe"),
    ("Linux", "build/linux/cdda2d.x86_64"),
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default=os.environ.get("GODOT", DEFAULT_GODOT))
    parser.add_argument("--only", choices=[preset for preset, _ in PRESETS], default=None)
    args = parser.parse_args()

    godot = Path(args.godot)
    if not godot.exists():
        print(f"Godot not found: {godot}")
        return 1

    targets = [pair for pair in PRESETS if args.only is None or pair[0] == args.only]
    for preset, relative in targets:
        output = ROOT / relative
        output.parent.mkdir(parents=True, exist_ok=True)
        command = [
            str(godot),
            "--headless",
            "--path",
            str(ROOT),
            "--export-release",
            preset,
            str(output),
        ]
        print("+ " + " ".join(command))
        result = subprocess.run(command)
        if result.returncode != 0:
            print(f"FAILED: {preset} (exit {result.returncode})")
            return result.returncode

    print("OK: " + ", ".join(preset for preset, _ in targets))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
