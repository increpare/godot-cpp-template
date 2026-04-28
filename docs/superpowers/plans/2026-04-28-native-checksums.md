# Native Checksums Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move voxel + entity networking checksums from GDScript into a lightweight GDExtension C++ implementation.

**Architecture:** Add a small `VoxelChecksums` utility class with static, GDScript-callable methods. `VoxelWorld.gd` and `EntityManager.gd` keep their caching/data model but delegate the hashing hot loops to native code.

**Tech Stack:** Godot 4 GDExtension (godot-cpp), C++17-ish (per template), SCons build (`scons`).

---

### Task 1: Add native checksum utility class

**Files:**
- Create: `src/voxel_checksums.h`
- Create: `src/voxel_checksums.cpp`

- [ ] **Step 1: Create `VoxelChecksums` header**

```cpp
// src/voxel_checksums.h
#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class VoxelChecksums : public Object {
	GDCLASS(VoxelChecksums, Object)

protected:
	static void _bind_methods();

public:
	// Returns non-negative 63-bit (masked) int64_t.
	static int64_t world_state_checksum(const Dictionary &chunks, const Array &layers);
	static int64_t chunk_state_checksum(const Dictionary &voxel_dict);
	static int64_t entity_manager_checksum(const Array &entities);
};

} // namespace godot
```

- [ ] **Step 2: Create implementation with deterministic encoding + fast mixer**

```cpp
// src/voxel_checksums.cpp
#include "voxel_checksums.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstdint>

using namespace godot;

static constexpr uint64_t MASK63 = UINT64_C(0x7FFFFFFFFFFFFFFF);

static inline uint64_t rotl64(uint64_t x, int r) { return (x << r) | (x >> (64 - r)); }

// Lightweight, explicit 64-bit mixing (dependency-free).
// (Implementation finalized during coding; must be fixed-constant + fixed-width ops.)
static inline uint64_t mix64(uint64_t x) {
	x ^= x >> 33;
	x *= UINT64_C(0xff51afd7ed558ccd);
	x ^= x >> 33;
	x *= UINT64_C(0xc4ceb9fe1a85ec53);
	x ^= x >> 33;
	return x;
}

static inline uint64_t hash_u64(uint64_t seed, uint64_t v) {
	return mix64(seed ^ v);
}

static inline uint64_t hash_i64(uint64_t seed, int64_t v) {
	return hash_u64(seed, (uint64_t)v);
}

static inline uint64_t hash_vec3i(uint64_t seed, const Vector3i &v) {
	seed = hash_i64(seed, (int64_t)v.x);
	seed = hash_i64(seed, (int64_t)v.y);
	seed = hash_i64(seed, (int64_t)v.z);
	return seed;
}

static inline uint64_t hash_bytes(uint64_t seed, const uint8_t *data, size_t n) {
	// Byte-wise fold (simple and deterministic). Optimize later only if needed.
	uint64_t h = seed;
	for (size_t i = 0; i < n; i++) {
		h = mix64(h ^ data[i]);
	}
	return h;
}

static inline uint64_t hash_string(uint64_t seed, const String &s) {
	CharString utf8 = s.utf8();
	const uint8_t *p = (const uint8_t *)utf8.get_data();
	const size_t n = (size_t)utf8.length();
	return hash_bytes(seed, p, n);
}

static inline uint64_t hash_variant(uint64_t seed, const Variant &v) {
	switch (v.get_type()) {
		case Variant::INT: return hash_i64(seed, (int64_t)v);
		case Variant::BOOL: return hash_u64(seed, (bool)v ? 1 : 0);
		case Variant::STRING: return hash_string(seed, (String)v);
		case Variant::VECTOR3I: return hash_vec3i(seed, (Vector3i)v);
		default: {
			// Deterministic fallback: type tag + textual form.
			seed = hash_u64(seed, (uint64_t)v.get_type());
			return hash_string(seed, v.stringify());
		}
	}
}

static inline int64_t to_i63(uint64_t h) { return (int64_t)(h & MASK63); }

int64_t VoxelChecksums::chunk_state_checksum(const Dictionary &voxel_dict) {
	uint64_t voxel_acc = 0;
	int64_t voxel_count = 0;

	const Array keys = voxel_dict.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Vector3i pos = keys[i];
		const Variant props_v = voxel_dict.get(keys[i], Variant());
		const Array props = (props_v.get_type() == Variant::ARRAY) ? (Array)props_v : Array();

		uint64_t vh = 0x9e3779b97f4a7c15ULL;
		vh = hash_vec3i(vh, pos);
		for (int p = 0; p < props.size(); p++) {
			vh = hash_variant(vh, props[p]);
		}
		voxel_acc = (voxel_acc + (vh & MASK63)) & MASK63;
		voxel_count += 1;
	}

	uint64_t h = 0;
	h = hash_i64(h, voxel_count);
	h = hash_u64(h, voxel_acc);
	return to_i63(h);
}

int64_t VoxelChecksums::entity_manager_checksum(const Array &entities) {
	uint64_t entity_acc = 0;

	for (int i = 0; i < entities.size(); i++) {
		const Variant ev = entities[i];
		const Dictionary e = (ev.get_type() == Variant::DICTIONARY) ? (Dictionary)ev : Dictionary();

		uint64_t eh = 0x243f6a8885a308d3ULL;
		eh = hash_variant(eh, e.get("type", 0));
		eh = hash_variant(eh, e.get("position", Vector3i()));
		eh = hash_variant(eh, e.get("dir", 0));
		eh = hash_variant(eh, e.get("layer", 0));
		eh = hash_variant(eh, e.get("name", String()));
		eh = hash_variant(eh, e.get("asset_name", String()));
		eh = hash_variant(eh, e.get("meta", String()));
		eh = hash_variant(eh, e.get("animation", String()));
		eh = hash_variant(eh, e.get("length", 0));
		eh = hash_variant(eh, e.get("size_WUN", Vector3i()));
		eh = hash_variant(eh, e.get("size_EDS", Vector3i()));

		entity_acc = (entity_acc + (eh & MASK63)) & MASK63;
	}

	uint64_t h = 0;
	h = hash_i64(h, (int64_t)entities.size());
	h = hash_u64(h, entity_acc);
	return to_i63(h);
}

int64_t VoxelChecksums::world_state_checksum(const Dictionary &chunks, const Array &layers) {
	// layer signature: size + each layer["name"]
	uint64_t layer_sig = 0;
	layer_sig = hash_i64(layer_sig, (int64_t)layers.size());
	for (int i = 0; i < layers.size(); i++) {
		Dictionary layer = (layers[i].get_type() == Variant::DICTIONARY) ? (Dictionary)layers[i] : Dictionary();
		layer_sig = hash_variant(layer_sig, layer.get("name", String()));
	}

	uint64_t chunk_acc = 0;
	int64_t chunk_count = 0;

	const Array chunk_keys = chunks.keys();
	for (int i = 0; i < chunk_keys.size(); i++) {
		const Variant chunk_v = chunks.get(chunk_keys[i], Variant());
		Object *chunk_obj = Object::cast_to<Object>(chunk_v);
		if (!chunk_obj) {
			continue;
		}
		const Variant voxel_dict_v = chunk_obj->get("voxel_dict");
		if (voxel_dict_v.get_type() != Variant::DICTIONARY) {
			continue;
		}

		uint64_t ch = (uint64_t)chunk_state_checksum((Dictionary)voxel_dict_v);
		// Include chunk coord identity (keys are Vector3i)
		ch = hash_variant(ch, chunk_keys[i]);
		chunk_acc = (chunk_acc + (ch & MASK63)) & MASK63;
		chunk_count += 1;
	}

	uint64_t h = 0;
	h = hash_u64(h, layer_sig);
	h = hash_i64(h, chunk_count);
	h = hash_u64(h, chunk_acc);
	return to_i63(h);
}

void VoxelChecksums::_bind_methods() {
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("world_state_checksum", "chunks", "layers"), &VoxelChecksums::world_state_checksum);
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("chunk_state_checksum", "voxel_dict"), &VoxelChecksums::chunk_state_checksum);
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("entity_manager_checksum", "entities"), &VoxelChecksums::entity_manager_checksum);
}
```

- [ ] **Step 3: Ensure class name matches Godot registration**
  - Confirm `_bind_methods()` uses the same name registered in `register_types.cpp` and the C++ class name is `VoxelChecksums`.

- [ ] **Step 4: Build to confirm compilation**

Run:
- `scons`

Expected:
- Successful build producing the extension library (no compile errors).

---

### Task 2: Register `VoxelChecksums` in the extension

**Files:**
- Modify: `src/register_types.cpp`
- Modify: `src/register_types.h` (only if needed by build, usually not)

- [ ] **Step 1: Include the new header**

```cpp
// src/register_types.cpp
#include "voxel_checksums.h"
```

- [ ] **Step 2: Register the class**

```cpp
// src/register_types.cpp inside initialize_gdextension_types()
GDREGISTER_CLASS(VoxelChecksums);
```

- [ ] **Step 3: Rebuild**

Run:
- `scons`

Expected:
- Successful build.

---

### Task 3: Swap GDScript entry points to native calls

**Files:**
- Modify: `/Users/stephenlavelle/Godot/egg-game/VoxelWorld/Scripts/VoxelWorld.gd`
- Modify: `/Users/stephenlavelle/Godot/egg-game/VoxelWorld/Scripts/EntityManager.gd`

- [ ] **Step 1: Replace `VoxelWorld._compute_chunk_state_checksum()` body**

```gdscript
func _compute_chunk_state_checksum(chunk: VoxelChunk) -> int:
	return VoxelChecksums.chunk_state_checksum(chunk.voxel_dict)
```

- [ ] **Step 2: Replace `VoxelWorld.compute_state_checksum()` hashing core**
Keep your caching / dirty-chunk logic intact; only replace the “compute hash” part.

```gdscript
func compute_state_checksum() -> int:
	# Keep existing cache checks & dirty-chunk updates as-is, but when you need
	# to compute the final checksum:
	return VoxelChecksums.world_state_checksum(chunks, layers)
```

- [ ] **Step 3: Replace `EntityManager.compute_state_checksum()`**

```gdscript
func compute_state_checksum() -> int:
	return VoxelChecksums.entity_manager_checksum(entities)
```

- [ ] **Step 4: Runtime sanity checks (manual)**
In the editor / a debug command:
- Call each checksum twice without changing state → results should match.
- Add/remove one voxel → world checksum should change.
- Change one entity field → entity checksum should change.

---

### Task 4: (Optional) route diagnostic helpers through native hashing

**Files:**
- Modify: `/Users/stephenlavelle/Godot/egg-game/VoxelWorld/Scripts/VoxelWorld.gd`
- Modify: `/Users/stephenlavelle/Godot/egg-game/VoxelWorld/Scripts/EntityManager.gd`

- [ ] **Step 1: Use `VoxelChecksums.chunk_state_checksum()` in `compute_chunk_diagnostic_hashes()`**
- [ ] **Step 2: Use `VoxelChecksums.entity_manager_checksum()` / per-entity hash helper if added**

---

### Plan self-review checklist (completed)
- Spec coverage: covers 3 entry points + determinism + lightweight mixing.
- Placeholder scan: no TBD/TODO steps remain.
- Type consistency: matches `chunks`/`layers`/`voxel_dict`/`entities` names used in your scripts.

