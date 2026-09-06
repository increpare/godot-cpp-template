# Native buffer and shared-corner performance

Preserve the public API, binary/text formats, vertex order, UVs, normals, colors, and editor triangle attribution while reducing repeated GDExtension calls.

Implemented:

- Binary save builds a native byte vector with explicit little-endian fields, then copies once into PackedByteArray. Binary load caches its owned immutable buffer's size and byte pointer for integer reads. Float/string decoding stays with the engine.
- Mesh triangle attribution accumulates in a reusable native vector and copies once to PackedInt32Array.
- Shape parsing classifies exact cube-corner vertices. Mesh generation shares only their noise displacement across adjacent voxels; local colors and normals retain the existing arithmetic. Non-corner vertices use the original path. The cache is cleared each chunk call; coordinates outside a conservative exact-half-integer float range use uncached noise.
- Fully hidden chunks return an empty mesh without attempting an invalid empty surface.

The simplified-mesh native-output-buffer experiment regressed real workloads and was discarded. Text parsing/writing and simplified meshing algorithms are unchanged.

## Measurements

Godot 4.6 custom build, Apple Silicon runtime, optimized clang C++17 template_debug libraries. Baseline native source revision: `6ae54b3`, compiled in the isolated harness; final candidate built with the repository’s normal `scons platform=macos target=template_debug arch=universal -j8` command. The final library contains arm64 and x86_64 slices; runtime tests used arm64. Production fixtures use the game’s actual 24³ chunks, read from VoxelChunk.gd. Earlier controlled builds with identical manual compiler flags also verified improvements on 16³ fixtures; the figures below are from the final production-size validation.

Median milliseconds over seven warmed iterations:

| Operation | eggworld before | after | mini_city before | after |
|---|---:|---:|---:|---:|
| Binary save | 14.067 | 8.234 | 25.568 | 15.073 |
| Binary load | 53.729 | 48.529 | 94.464 | 86.743 |
| Detailed mesh generation | 326.730 | 281.813 | 572.627 | 483.423 |
| Simplified mesh generation | 64.262 | 63.380 | 124.544 | 123.150 |
| Text save | 14.313 | 14.249 | 25.560 | 25.432 |
| Text load | 59.154 | 58.726 | 106.414 | 105.739 |

The fixtures contain 165,801 voxels / 256 chunks and 299,291 voxels / 483 chunks. Detailed mesh time fell 13.7% and 15.6%; binary save 41.5% and 41.0%; binary load 9.7% and 8.2%. Synthetic detailed meshing with 16³ chunks: solid 2.673 → 1.849 ms, checkerboard 6.147 → 5.332 ms, mixed shapes 13.459 → 13.129 ms. Timing thresholds are not asserted; PASS denotes output/behavior agreement.

All compared output signatures matched exactly, including signed/Unicode/truncated binary data, all shape variants, and very large coordinates. The native face-culling subset and the existing entity-attribution serializer contract passed. The sandboxed engine reports a system certificate-access warning unrelated to these tests. See tests/README.md for reproduction and the existing GDScript alias-test limitation.

These timings exclude level scene construction, disk I/O, physics collision creation, and GPU upload. No end-to-end load-time claim is implied.

## Memory and compatibility

The production 24³ chunk’s shared-corner cache uses about 198 KiB (15,625 Vector3 displacements plus validity bytes with single precision); a 16³ chunk uses about 64 KiB. Mesh buffers retain capacity between calls, as the existing mesher already does. Binary save temporarily retains its native bytes while copying the final PackedByteArray, adding about one output-buffer size of peak memory. The mesher remains non-reentrant due to its existing reusable member buffers.

Windows/Linux and release distributions must be rebuilt from the updated sources before shipping. No network protocol or save version bump is required.

The rebuilt macOS template_debug library is installed in the game for editor/debug playtesting. Restart any running Godot instance to load it. Release and other-platform binaries were not rebuilt.
