# Native performance regression harness

The harness runs in a temporary Godot project using the game's current shape definitions. It does not modify the game project or load player saves. Requires Python 3, Godot 4.6, and a built extension for the current platform. Compile baseline and candidate with identical flags and the same godot-cpp library.

Before replacing the baseline extension, preserve it outside the build directory. Record its signatures, then compare the candidate:

```sh
python3 tests/run_performance.py \
  --godot /Applications/GodotSteam.app/Contents/MacOS/Godot \
  --game-project /Users/stephenlavelle/Godot/egg-game \
  --library /tmp/oeuf-baseline.dylib \
  --record /tmp/oeuf-baseline.json

python3 tests/run_performance.py \
  --godot /Applications/GodotSteam.app/Contents/MacOS/Godot \
  --game-project /Users/stephenlavelle/Godot/egg-game \
  --library demo/bin/macos/libEXTENSION-NAME.macos.template_debug.dylib \
  --compare /tmp/oeuf-baseline.json
```

Use the actual Godot executable with `--godot`; the local `/usr/local/bin/godot` wrapper currently has a blank line before its shebang, so Python cannot execute it directly. On other platforms supply the appropriate executable and extension library.

Coverage:

- Both bundled levels: binary bytes, binary decoded data, serialized text, and every chunk's complete render/simplified mesh arrays and triangle attribution.
- All 104 shape/rotation/flip combinations, negative and very large coordinates, changing dimensions, reconfiguration, hidden layers, empty chunks, solid/checkerboard/mixed chunks.
- Signed coordinate boundaries, Unicode/escaped/empty strings, binary roundtrip, and truncated binary prefixes.
- Existing face occupancy tests, except the full-game grout test and three alias-dependent tests already failing on baseline because `occupancy_alias(_name)` reads `occupancy_aliases[name]`. The harness does not alter production shapes to hide that bug.

The real-level mesh tests read the production dimensions from VoxelChunk.gd (currently 24³). Synthetic cases retain their explicitly chosen dimensions.

Timings are medians of seven warmed runs. Signature generation, fixture loading/grouping, and assertions occur outside the timed mesh loops. These are headless native-call measurements, not complete gameplay load times (collision creation, rendering upload on a real GPU, scene construction, and disk I/O are not measured).

The fixture adapter deliberately checks the relevant game script text before replacing texture loading and removing unrelated singleton dependencies. If those scripts change, update the adapter rather than interpreting fixture setup errors as native regressions. Baseline recording permits the existing hidden-chunk empty-surface error; candidate comparison rejects it.

## Direct chunk text saving

`run_direct_save.py` creates an isolated temporary project and checks exact text equivalence between the existing row API and the new chunk-array API, including legacy properties, ordering, Unicode metadata and entity versions. It also times preparation plus serialization on both sample levels.

```sh
python3 tests/run_direct_save.py \
  --godot /Applications/GodotSteam.app/Contents/MacOS/Godot \
  --library bin/macos/libEXTENSION-NAME.macos.template_debug.dylib
```

`serializer_compatibility.gd` can additionally be run in a fixture project containing `res://sample_files` and either library to compare existing text/binary hashes across builds. It prints signatures rather than asserting equality by itself.

See [the GDScript/native integration report](../docs/load-save-interface-performance-2026-09-06.md) for actual EditorUI save timings, budgeted loading, conditional simplified meshes, and game-side regression commands.

## Chunk-boundary meshing

`run_boundary.py` compares partitioned meshes against a unified-chunk oracle using the game's actual shapes: 64,896 ordered shape/rotation/flip/direction pairs, hidden layers, negatives, empty and missing neighbors, full vertex attributes and editor triangle attribution.

```sh
python3 tests/run_boundary.py \
  --godot /Applications/GodotSteam.app/Contents/MacOS/Godot \
  --game-project /Users/stephenlavelle/Godot/egg-game \
  --library bin/macos/libEXTENSION-NAME.macos.template_debug.dylib
```

Add `--benchmark` to compare the two APIs in the same binary on sample levels, plus repeatable `--level '/path/to/level.txt'` arguments for extra read-only fixtures. Add `--compatibility` to print an old-API fingerprint for comparison across builds.

See [the boundary-culling report](../docs/chunk-boundary-culling-2026-09-06.md) for game-side edit/undo/resync coverage, large-level results and all-quality culling and the remaining detailed/LOD seam tradeoff.
