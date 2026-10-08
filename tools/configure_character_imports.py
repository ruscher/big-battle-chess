#!/usr/bin/env python3
"""Configures Godot import settings for the locally built character textures.

Godot imports textures referenced by glTF files as lossless and without
mipmaps until the editor detects 3D usage. This script switches every
texture under assets/characters_ext/ to VRAM compression with mipmaps
(normal maps flagged as normal maps, size-limited ORM maps) and then asks
Godot to re-import. Run after tools/blender/build_characters.py:

    python3 tools/configure_character_imports.py [--godot godot]
"""
import argparse
import glob
import os
import re
import subprocess

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
TEX_GLOB = os.path.join(ROOT, "assets", "characters_ext", "*", "textures", "*.import")


def set_param(text, key, value):
    pattern = re.compile(rf"^{re.escape(key)}=.*$", re.M)
    if pattern.search(text):
        return pattern.sub(f"{key}={value}", text)
    return text.replace("[params]\n", f"[params]\n\n{key}={value}\n", 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default="godot")
    args = ap.parse_args()
    files = glob.glob(TEX_GLOB)
    if not files:
        print("no .import files yet: running a first import")
        subprocess.run([args.godot, "--headless", "--path", ROOT, "--import"], check=False)
        files = glob.glob(TEX_GLOB)
    changed = 0
    for path in files:
        name = os.path.basename(path).lower()
        with open(path) as f:
            text = f.read()
        before = text
        is_normal = "normal" in name
        is_orm = "orm" in name or "metallic" in name or "roughness" in name
        text = set_param(text, "compress/mode", 2)               # VRAM compressed (BPTC/S3TC, ETC2/ASTC)
        text = set_param(text, "compress/high_quality", "true" if not is_orm else "false")
        text = set_param(text, "compress/normal_map", 1 if is_normal else 2)
        text = set_param(text, "mipmaps/generate", "true")
        text = set_param(text, "detect_3d/compress_to", 0)
        text = set_param(text, "process/size_limit", 2048 if is_orm else 0)
        if text != before:
            with open(path, "w") as f:
                f.write(text)
            changed += 1
    print(f"{changed}/{len(files)} texture import files updated")
    subprocess.run([args.godot, "--headless", "--path", ROOT, "--import"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("re-import done")


if __name__ == "__main__":
    main()
