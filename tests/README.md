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
