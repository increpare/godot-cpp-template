# GDScript/native load and text-save performance — 2026-09-06

> Historical measurements: the conditional/lazy LOD policy below was subsequently replaced at the user’s request. Current code eagerly generates LODs alongside culled detailed meshes at every quality, so quality switches generate neither mesh. See [the current boundary-culling report](chunk-boundary-culling-2026-09-06.md).

Three bounded changes retained after measuring each stage. Game chunk dimensions remain 24³. Native baseline is e439369589c874248fab3b3841e8d7eb9785a9b9, which already contains the earlier buffer and shared-corner improvements.

## Changes and complexity decisions

- **Budget chunk loading by elapsed time.** VoxelWorld.restore_from_data previously yielded once for every chunk. It now regenerates chunks until 4 ms has elapsed, then yields. Existing ordering and initial yields remain; cancellation is checked before each chunk, immediately after every yield, and before successful completion. The final check also handles cancellation raised during the last chunk. This is a soft budget: a chunk is indivisible and can exceed it. No worker scheduling, queues, or new asynchronous ownership.
- **Build simplified meshes only at quality 0.** They were previously generated at every quality even though only quality 0 displayed them. Detailed remeshing marks the simplified mesh dirty. Low-quality loading builds it immediately; switching from higher quality builds missing/dirty meshes on demand. Existing MeshInstance3D nodes are reused, preserving their material, visibility and offset. Cached meshes remain allocated after switching to higher quality, so later switches reuse them. One dirty flag replaces repeated node allocation.
- **Pass existing chunk arrays directly to native text serialization.** EditorUI collects two arrays of chunk-array references and captures metadata/camera/entities without constructing a new seven-field GDScript row per voxel. The new serialize_chunks_to_string API shares the old text writer. Snapshot, binary and existing native APIs retain their paths and formats. GDScript checks method availability and calls dynamically, allowing older platform extensions to keep saving. Duplicate imported positions fall back to the old dictionary-based path via an O(1) size check per chunk. No persistent native voxel store or second format implementation.

## Actual voxel-loading pipeline

Godot 4.6 custom build, Apple Silicon runtime, macOS universal template_debug extension built with the repository's normal SCons command. Headless game fixture capped at 60 FPS. Times include text parsing, voxel ingestion, real GDScript visibility decisions, detailed/simplified native meshing and physics collision creation. They exclude disk reads, full entity/level scene setup, surrounding editor UI and real GPU upload/rendering. These are representative individual runs per stage, not medians or complete gameplay loading times.

| Stage | eggworld quality 1 | mini_city quality 1 | eggworld quality 0 | mini_city quality 0 |
|---|---:|---:|---:|---:|
| Original, one chunk/frame | 4.566 s | 8.581 s | 4.554 s | 8.563 s |
| 4 ms budget only | 2.337 s | 4.112 s | 2.367 s | 4.034 s |
| Final, budget + conditional LOD | 2.115 s | 3.630 s | 2.344 s | 3.950 s |

Most of the elapsed saving comes from eliminating unnecessary frame waits, rather than making the CPU execute twice as fast. At quality 1, actual chunk-regeneration CPU time fell from 811 to 688 ms and 1,463 to 1,199 ms. Final quality-1 loads built zero simplified meshes; quality-0 loads built all 256/483.

Every stage produced the same 165,801/299,291 voxel counts, 670,296/1,167,648 detailed triangles and world checksums 2220433626783586344/7578368576681345440.

**Quality-switch tradeoff:** first high-to-low refresh built the deferred meshes in 68.7 ms / 131.4 ms. A subsequent high-to-low refresh reused them in 0.56 ms / 1.05 ms. This introduces a short first-switch hitch in the settings flow. Retained the synchronous cache because avoiding that hitch would require additional scheduling and intermediate rendering state; reconsider only if playtesting shows the settings transition needs it.

## Actual EditorUI text saving

Same final SCons-built library for both paths; real VoxelWorld/VoxelChunk objects and EditorUI snapshot preparation, including camera and EntityManager capture. One warmup per path, seven samples each, alternating execution order. No disk write. Mesh generation is disabled while constructing these save fixtures and occurs outside timing. Every timed string matched the legacy path exactly and world checksums remained unchanged.

| Level | Legacy median | Direct chunk median | Speedup |
|---|---:|---:|---:|
| eggworld.txt | 77.933 ms | 15.665 ms | 4.98× |
| mini_city.txt | 141.766 ms | 28.630 ms | 4.95× |

The native-only writer was already fast. The gain comes from removing GDScript flattening and dictionary lookups before it. The bounded API addition saves approximately 62/113 ms per text snapshot and avoids hundreds of thousands of temporary row arrays on these samples.

## Verification

- New runtime contracts passed: cheap chunks share frames, expensive chunks yield, cancellation at an intermediate/final chunk completes exactly once, empty load, quality switching, deferred edits, cached node reuse and stable offset, empty mesh removal, real near/far material/visibility/collision selection and camera movement.
- Actual EditorUI output matches legacy text for ordinary, empty and duplicate-position worlds. Ran the same contract with both the old installed extension (fallback) and the new extension (direct path).
- Native direct-save tests pass typed and empty chunk arrays, insertion/delta-boundary/negative positions, legacy five-property rows without mutation, escaped/Unicode metadata, entity versions 0/5/6 and both complete sample levels. New API presence test failed before implementation and passed afterward.
- Independently built committed baseline and final SCons library produce identical existing-API text/binary hashes for both levels and text hashes for entity versions 0/5/6.
- Existing entity-attribution serializer, voxel chunk index and full snapshot/history tests passed. Authoritative transition runtime lifecycle checks passed. Updated two source assertions to recognize budgeted chunk loading; two unrelated assertions about host load handlers still fail identically against the original committed files and final files. The complete static transition suite is therefore not green.
- Godot emitted existing headless Steam/display/certificate warnings and some shutdown leak warnings. No SCRIPT ERROR in passing focused runs. Build succeeded and both repositories pass git diff --check. Independent code review found no blocker.

The Mac universal debug extension is installed in the game. Restart Godot to load it. Release and Windows binaries that were already modified before this pass were preserved; rebuild them from the new source to enable the direct-save path there. GDScript pacing/LOD changes and the older-library save fallback do not require the new method.

## Reproduction

From the native repository:

```sh
scons platform=macos target=template_debug arch=universal -j8
python3 tests/run_direct_save.py \
  --godot /Applications/GodotSteam.app/Contents/MacOS/Godot \
  --library bin/macos/libEXTENSION-NAME.macos.template_debug.dylib
```

From the game repository, with its matching extension installed:

```sh
godot --headless --path . res://scripts/test_load_mesh_performance.tscn
godot --headless --path . res://scripts/test_load_mesh_performance.tscn -- \
  --bench --samples=/path/to/godot-cpp-template/sample_files
godot --headless --path . res://scripts/test_load_mesh_performance.tscn -- \
  --save-bench --samples=/path/to/godot-cpp-template/sample_files
```

Use an explicit writable --log-file in restricted environments. Timings are reported rather than asserted. Full game fixtures load project autoloads; use a development profile. Raw logs for this run are in /private/tmp/oeuf-interface-pass.

Cross-chunk native culling, persistent native voxel ownership, full native bulk loading and alternative collision construction remain deferred. These retained changes provide measured gains without expanding into those larger architectural changes.
