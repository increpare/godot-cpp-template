## Native checksums for voxel + entity state (design)

### Context
`VoxelWorld.gd` and `EntityManager.gd` compute state checksums in GDScript for networking/desync detection. The hot paths are:

- `VoxelWorld.compute_state_checksum()`
- `VoxelWorld._compute_chunk_state_checksum(chunk)`
- `EntityManager.compute_state_checksum()`

The current GDScript implementation is already structured to avoid expensive sorting by using **order-independent reduction** (modular sum) over per-voxel/per-entity hashes, but still pays heavy per-element interpreter + function-call overhead.

### Goals / non-goals
- **Goals**
  - Replace the above entry points with **native (GDExtension C++)** implementations.
  - Keep the checksums **deterministic** for a given build/platform and input state.
  - Keep the implementation **lightweight** (no large dependencies).
  - Maintain the existing caching strategy in `VoxelWorld.gd` (dirty chunks, per-chunk cache), swapping only the hashing core.
- **Non-goals**
  - Cryptographic security.
  - Backwards compatibility with previous numeric checksum outputs.
  - Eliminating all Variant overhead (data stays as `Dictionary`/`Array` in GDScript).

### Proposed solution (recommended)
Add a new GDExtension utility class (static methods) that performs hashing/mixing in C++:

- **Class**: `VoxelChecksums` (name can be adjusted)
- **Registration**: `GDREGISTER_CLASS(VoxelChecksums);` in `src/register_types.cpp`

#### Public API (GDScript-callable)
All functions return a non-negative 63-bit `int` (mask with `0x7FFFFFFFFFFFFFFF`) to be friendly with GDScript `int`.

- `static func world_state_checksum(chunks: Dictionary, layers: Array) -> int`
  - `chunks` is the `VoxelWorld.chunks` dictionary: keys `Vector3i` chunk coords; values `VoxelChunk` objects.
  - `layers` is `VoxelWorld.layers` array of dicts with at least `"name"`.
  - Implementation:
    - Compute `layer_signature` from `layers.size()` and each layer name.
    - Combine per-chunk hashes order-independently into `chunk_acc` (modular sum).
    - Mix in `layer_signature`, `chunk_count`, `chunk_acc`.

- `static func chunk_state_checksum(voxel_dict: Dictionary) -> int`
  - `voxel_dict` is `VoxelChunk.voxel_dict`: keys `Vector3i` voxel coords; values voxel props `Array`.
  - Implementation:
    - For each voxel:
      - Hash voxel coordinate + each prop element (see “Deterministic field encoding” below).
      - Sum voxel hashes order-independently into `voxel_acc`.
    - Mix in `voxel_count` and `voxel_acc`.

- `static func entity_manager_checksum(entities: Array) -> int`
  - `entities` is `EntityManager.entities`: array of `Dictionary`.
  - Implementation:
    - For each entity dictionary, hash gameplay-relevant fields (below) into `eh`.
    - Sum entity hashes order-independently into `entity_acc`.
    - Mix in `entities.size()` and `entity_acc`.

#### Fields included (entity hashing)
Hash (in this order) the same gameplay-relevant fields as the current GDScript:

- `type` (int)
- `position` (Vector3i: x,y,z)
- `dir` (int)
- `layer` (int)
- `name` (String)
- `asset_name` (String)
- `meta` (String)
- `animation` (String)
- `length` (int)
- `size_WUN` (Vector3i: x,y,z)
- `size_EDS` (Vector3i: x,y,z)

Missing keys use the same defaults as current GDScript (0 / empty / `Vector3i.ZERO`).

### Hash/mix choice
Use a **fast non-crypto 64-bit mixer** implemented directly in the extension (dependency-free), then mask to 63-bit.

Constraints:
- Small code footprint
- Strong avalanche for structured inputs (better than raw FNV-1a)
- Deterministic across platforms/compilers

Implementation detail: we will implement an explicit 64-bit mixing function with fixed constants and fixed-width operations; no reliance on `std::hash` or Godot’s internal Variant hash.

### Deterministic field encoding
To ensure determinism:

- **Integers/bools**: encode as fixed-width signed 64-bit (or 32-bit where explicitly chosen), then mix.
- **Vector3i**: encode x/y/z as signed 32-bit (or 64-bit), mixed in a fixed order.
- **Strings**: encode as UTF-8 bytes, mixed byte-wise or word-wise in a fixed order.
- **Voxel props (`Array`)**:
  - Prefer strict handling for common types used in voxel props: `int`, `bool`.
  - If unexpected types appear, fall back to hashing `(Variant::get_type(), String(variant))` (deterministic but slower).

### Integration plan (GDScript)
- In `VoxelWorld.gd`:
  - Replace the body of `compute_state_checksum()` to call `VoxelChecksums.world_state_checksum(chunks, layers)` and keep existing caching logic intact.
  - Replace `_compute_chunk_state_checksum(chunk)` to call `VoxelChecksums.chunk_state_checksum(chunk.voxel_dict)`.
- In `EntityManager.gd`:
  - Replace the body of `compute_state_checksum()` to call `VoxelChecksums.entity_manager_checksum(entities)`.

Optional follow-up (not required for initial change):
- Update diagnostic helpers (`compute_chunk_diagnostic_hashes`, `compute_entity_diagnostic_hashes`) to reuse the same native per-chunk/per-entity hashing.

### Error handling / safety
- All native functions should be defensive:
  - Accept `Variant` types but validate and treat unexpected shapes as empty/default rather than crashing.
  - Never throw exceptions across the GDExtension boundary.

### Testing / verification
- Add a small “sanity test” GDScript (or a debug command) that:
  - Computes checksum via native functions twice and asserts equality.
  - Mutates a single voxel prop and asserts checksum changes.
  - Mutates a single entity field and asserts checksum changes.

### Rollout
- Replace the GDScript entry points first.
- Keep the old GDScript hashing code around temporarily (behind an optional debug toggle) only if needed for cross-check during development; remove once stable.

