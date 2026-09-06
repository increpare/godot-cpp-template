#!/usr/bin/env python3
"""Run direct chunk save regression tests and timings in an isolated Godot project."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--library", type=Path, required=True,
                        help="Built macOS dylib, Linux so, or Windows dll")
    parser.add_argument("--godot", default="godot", help="Godot executable path or command")
    args = parser.parse_args()
    native = Path(__file__).resolve().parent.parent
    library = args.library.resolve()
    platforms = {".dylib": "macos", ".so": "linux", ".dll": "windows"}
    if not library.is_file():
        parser.error(f"Library not found: {library}")
    if library.suffix.lower() not in platforms:
        parser.error("Library must end in .dylib, .so, or .dll")
    if shutil.which(args.godot) is None:
        parser.error(f"Godot executable not found: {args.godot}")
    for name in ("eggworld.txt", "mini_city.txt"):
        if not (native / "sample_files" / name).is_file():
            parser.error(f"Sample not found: {native / 'sample_files' / name}")

    with tempfile.TemporaryDirectory(prefix="oeuf-direct-save-") as directory:
        root = Path(directory)
        (root / "bin").mkdir()
        (root / "tests").mkdir()
        (root / ".godot").mkdir()
        filename = "native" + library.suffix.lower()
        shutil.copy2(library, root / "bin" / filename)
        shutil.copytree(native / "sample_files", root / "sample_files")
        shutil.copy2(native / "tests/direct_save.gd", root / "tests/direct_save.gd")
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="godot cpp template"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding="utf-8")
        platform = platforms[library.suffix.lower()]
        (root / "bin/native.gdextension").write_text(
            '[configuration]\nentry_symbol="example_library_init"\ncompatibility_minimum="4.1"\n'
            f'[libraries]\n{platform}="res://bin/{filename}"\n', encoding="utf-8")
        (root / ".godot/extension_list.cfg").write_text("res://bin/native.gdextension\n", encoding="utf-8")
        result = subprocess.run(
            [args.godot, "--headless", "--log-file", str(root / "engine.log"),
             "--path", str(root), "--script", "res://tests/direct_save.gd"],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
        output = result.stdout + result.stderr
        print(output, end="")
        if (result.returncode or re.search(r"^FAILURES\s+0\s*$", output, re.MULTILINE) is None
                or "SCRIPT ERROR" in output):
            raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
