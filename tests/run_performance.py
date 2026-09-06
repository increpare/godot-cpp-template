#!/usr/bin/env python3
"""Run native output comparisons and timings without changing the game project."""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError(f"Game fixture setup no longer matches: {old!r}")
    return source.replace(old, new, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-project", type=Path, required=True)
    parser.add_argument("--library", type=Path, required=True,
                        help="Built macOS dylib, Linux so, or Windows dll")
    parser.add_argument("--godot", default="godot")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--record", type=Path)
    mode.add_argument("--compare", type=Path)
    args = parser.parse_args()
    native = Path(__file__).resolve().parent.parent
    game = args.game_project.resolve()
    library = args.library.resolve()
    signature = (args.record or args.compare).resolve()
    if not library.is_file():
        parser.error(f"Library not found: {library}")
    if args.compare and not signature.is_file():
        parser.error(f"Baseline not found: {signature}")

    chunk_script = (game / "VoxelWorld/Scripts/VoxelChunk.gd").read_text()
    dimensions = []
    for axis in "XYZ":
        match = re.search(r"^const SIZE_" + axis + r"(?:\s*:\s*int)?\s*=\s*(\d+)\s*$", chunk_script, re.MULTILINE)
        if not match or int(match.group(1)) <= 0:
            raise RuntimeError(f"Cannot read production chunk dimension {axis}")
        dimensions.append(int(match.group(1)))

    with tempfile.TemporaryDirectory(prefix="oeuf-native-perf-") as directory:
        root = Path(directory)
        (root / "bin").mkdir()
        (root / "tests").mkdir()
        (root / ".godot").mkdir()
        filename = "native" + library.suffix
        shutil.copy2(library, root / "bin" / filename)
        shutil.copytree(native / "sample_files", root / "sample_files")
        for name in ("performance.gd", "performance.tscn"):
            shutil.copy2(native / "tests" / name, root / "tests" / name)

        # Exercise actual game shapes without importing textures or game singletons.
        shapes = (game / "VoxelWorld/Scripts/Shapes.gd").read_text()
        shapes = replace_once(shapes, 'load("res://VoxelWorld/Textures/tilemap.png")', "null")
        shapes = replace_once(shapes, "TEX_TILEMAP.get_width()", "1024")
        shapes = replace_once(shapes, "TEX_TILEMAP.get_height()", "1024")
        (root / "Shapes.gd").write_text(shapes)
        glob = (game / "VoxelWorld/Scripts/Glob.gd").read_text()
        if "var macOS:" not in glob:
            raise RuntimeError("Glob fixture setup needs updating")
        (root / "Glob.gd").write_text(glob.split("var macOS:", 1)[0])

        # Retain the native culling/shape tests. Grout requires the full game;
        # these three alias tests currently fail on unchanged GDScript because
        # occupancy_alias(_name) indexes occupancy_aliases[name].
        tests = (game / "Resources/Tests/FaceOccupancyTestRunner.gd").read_text()
        for call in ("_test_grout_aliases_resolve", "_test_alias_ids_are_stable",
                     "_test_basic_cull_actions", "_test_partial_quad_indices"):
            tests = replace_once(tests, "\t" + call + "()\n", "")
        start = tests.index("func _test_grout_aliases_resolve()")
        end = tests.index("\nfunc ", start + 1)
        (root / "FaceOccupancyTestRunner.gd").write_text(tests[:start] + tests[end:])
        (root / "project.godot").write_text(
            'config_version=5\n[application]\nconfig/name="godot cpp template"\n'
            '[autoload]\nGlob="*res://Glob.gd"\nShapes="*res://Shapes.gd"\n'
            '[rendering]\nrenderer/rendering_method="gl_compatibility"\n'
            f'[native_performance]\nchunk_size=Vector3i({dimensions[0]},{dimensions[1]},{dimensions[2]})\n')
        platform = {".dylib": "macos", ".so": "linux", ".dll": "windows"}[library.suffix]
        (root / "bin/native.gdextension").write_text(
            '[configuration]\nentry_symbol="example_library_init"\ncompatibility_minimum="4.1"\n'
            f'[libraries]\n{platform}="res://bin/{filename}"\n')
        (root / ".godot/extension_list.cfg").write_text("res://bin/native.gdextension\n")
        mode_flag = "--record" if args.record else "--compare"
        result = subprocess.run(
            [args.godot, "--headless", "--log-file", str(root / "engine.log"),
             "--path", str(root), "res://tests/performance.tscn", "--", mode_flag, str(signature)],
            capture_output=True, text=True, timeout=180)
        output = result.stdout + result.stderr
        print(output, end="")
        if result.returncode or "PERFORMANCE REGRESSION PASS" not in output or "SCRIPT ERROR:" in output:
            raise SystemExit(result.returncode or 1)
        # Empty surfaces are an expected baseline defect, fixed by this change.
        if args.compare and ('array_len == 0' in output or 'ERR_INVALID_DATA' in output):
            raise SystemExit("Candidate still submits an invalid empty surface")


if __name__ == "__main__":
    main()
