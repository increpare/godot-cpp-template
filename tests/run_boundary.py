#!/usr/bin/env python3
"""Run boundary meshing tests against actual game shapes in an isolated project."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-project", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--godot", default="godot")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--compatibility", action="store_true", help="Print the existing mesh API signature")
    mode.add_argument("--benchmark", action="store_true", help="Benchmark repository samples and optional --level files")
    parser.add_argument("--level", action="append", type=Path, default=[], help="Additional read-only benchmark level")
    args = parser.parse_args()
    native = Path(__file__).resolve().parent.parent
    game = args.game_project.resolve()
    library = args.library.resolve()
    platforms = {".dylib":"macos", ".so":"linux", ".dll":"windows"}
    if not library.is_file() or library.suffix.lower() not in platforms:
        parser.error("Supply an existing .dylib, .so or .dll library")
    with tempfile.TemporaryDirectory(prefix="oeuf-boundary-tests-") as directory:
        root = Path(directory)
        for name in ("bin", "tests", ".godot"):
            (root / name).mkdir()
        filename = "native" + library.suffix.lower()
        shutil.copy2(library,root / "bin" / filename)
        script = "boundary_compatibility.gd" if args.compatibility else ("boundary_benchmark.gd" if args.benchmark else "boundary.gd")
        if args.benchmark:
            shutil.copytree(native / "sample_files",root / "sample_files")
        shutil.copy2(native / "tests" / script,root / "tests" / script)
        shapes = (game / "VoxelWorld/Scripts/Shapes.gd").read_text(encoding="utf-8")
        for old, new in [('load("res://VoxelWorld/Textures/tilemap.png")', "null"),
                         ("TEX_TILEMAP.get_width()", "1024"), ("TEX_TILEMAP.get_height()", "1024")]:
            if shapes.count(old) != 1:
                raise RuntimeError(f"Shape fixture setup no longer matches {old!r}")
            shapes = shapes.replace(old,new,1)
        (root / "Shapes.gd").write_text(shapes,encoding="utf-8")
        glob = (game / "VoxelWorld/Scripts/Glob.gd").read_text(encoding="utf-8")
        if "var macOS:" not in glob:
            raise RuntimeError("Glob fixture setup needs updating")
        (root / "Glob.gd").write_text(glob.split("var macOS:",1)[0],encoding="utf-8")
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="godot cpp template"\n'
            '[autoload]\nGlob="*res://Glob.gd"\nShapes="*res://Shapes.gd"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding="utf-8")
        platform = platforms[library.suffix.lower()]
        (root / "bin/native.gdextension").write_text(
            '[configuration]\nentry_symbol="example_library_init"\ncompatibility_minimum="4.1"\n'
            f'[libraries]\n{platform}="res://bin/{filename}"\n',encoding="utf-8")
        (root / ".godot/extension_list.cfg").write_text("res://bin/native.gdextension\n",encoding="utf-8")
        result = subprocess.run([args.godot,"--headless","--log-file",str(root / "engine.log"),
            "--path",str(root),"--script","res://tests/" + script,"--",
            *[str(level.resolve()) for level in args.level]],
            capture_output=True,text=True,encoding="utf-8",errors="replace",timeout=180)
        output = result.stdout + result.stderr
        print(output,end="")
        marker = "OLD API SIGNATURE " if args.compatibility else ("BOUNDARY BENCH PASS" if args.benchmark else "BOUNDARY REGRESSION PASS")
        if result.returncode or marker not in output or "SCRIPT ERROR" in output:
            raise SystemExit(result.returncode or 1)


if __name__ == "__main__":
    main()
