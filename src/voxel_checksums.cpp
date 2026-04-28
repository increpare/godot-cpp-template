#include "voxel_checksums.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3i.hpp>

#include <cstddef>
#include <cstdint>

using namespace godot;

static constexpr uint64_t MASK63 = UINT64_C(0x7FFFFFFFFFFFFFFF);

static inline uint64_t mix64(uint64_t x) {
	// MurmurHash3 fmix64 (public domain-like; widely used non-crypto finalizer).
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
	uint64_t h = seed;
	for (size_t i = 0; i < n; i++) {
		h = mix64(h ^ (uint64_t)data[i]);
	}
	return h;
}

static inline uint64_t hash_string(uint64_t seed, const String &s) {
	CharString utf8 = s.utf8();
	const uint8_t *p = reinterpret_cast<const uint8_t *>(utf8.get_data());
	const size_t n = static_cast<size_t>(utf8.length());
	return hash_bytes(seed, p, n);
}

static inline uint64_t hash_variant(uint64_t seed, const Variant &v) {
	switch (v.get_type()) {
		case Variant::INT:
			return hash_i64(seed, (int64_t)v);
		case Variant::BOOL:
			return hash_u64(seed, (bool)v ? 1 : 0);
		case Variant::STRING:
			return hash_string(seed, (String)v);
		case Variant::VECTOR3I:
			return hash_vec3i(seed, (Vector3i)v);
		case Variant::FLOAT: {
			// Deterministic bit-level hashing for float64.
			double d = (double)v;
			uint64_t bits;
			static_assert(sizeof(double) == sizeof(uint64_t), "double must be 64-bit");
			__builtin_memcpy(&bits, &d, sizeof(bits));
			return hash_u64(seed, bits);
		}
		default: {
			// Deterministic fallback: type tag + stringified form.
			seed = hash_u64(seed, (uint64_t)v.get_type());
			return hash_string(seed, v.stringify());
		}
	}
}

static inline int64_t to_i63(uint64_t h) {
	return (int64_t)(h & MASK63);
}

int64_t VoxelChecksums::chunk_state_checksum(const Dictionary &voxel_dict) {
	uint64_t voxel_acc = 0;
	int64_t voxel_count = 0;

	const Array keys = voxel_dict.keys();
	for (int i = 0; i < keys.size(); i++) {
		const Variant key = keys[i];
		if (key.get_type() != Variant::VECTOR3I) {
			continue;
		}
		const Vector3i pos = (Vector3i)key;

		const Variant props_v = voxel_dict.get(key, Variant());
		const Array props = (props_v.get_type() == Variant::ARRAY) ? (Array)props_v : Array();

		uint64_t vh = UINT64_C(0x9e3779b97f4a7c15);
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

		uint64_t eh = UINT64_C(0x243f6a8885a308d3);
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
	// Layer signature: size + each layer["name"] (matches current GDScript intent).
	uint64_t layer_sig = (uint64_t)layers_signature(layers);

	uint64_t chunk_acc = 0;
	int64_t chunk_count = 0;

	const Array chunk_keys = chunks.keys();
	for (int i = 0; i < chunk_keys.size(); i++) {
		const Variant ck = chunk_keys[i];
		const Variant chunk_v = chunks.get(ck, Variant());

		Object *chunk_obj = Object::cast_to<Object>(chunk_v);
		if (!chunk_obj) {
			continue;
		}

		const Variant voxel_dict_v = chunk_obj->get("voxel_dict");
		if (voxel_dict_v.get_type() != Variant::DICTIONARY) {
			continue;
		}

		uint64_t ch = (uint64_t)chunk_state_checksum((Dictionary)voxel_dict_v);
		// Include chunk coordinate identity (coord keys are Vector3i).
		ch = hash_variant(ch, ck);

		chunk_acc = (chunk_acc + (ch & MASK63)) & MASK63;
		chunk_count += 1;
	}

	uint64_t h = 0;
	h = hash_u64(h, layer_sig);
	h = hash_i64(h, chunk_count);
	h = hash_u64(h, chunk_acc);
	return to_i63(h);
}

int64_t VoxelChecksums::layers_signature(const Array &layers) {
	uint64_t layer_sig = 0;
	layer_sig = hash_i64(layer_sig, (int64_t)layers.size());
	for (int i = 0; i < layers.size(); i++) {
		const Variant lv = layers[i];
		const Dictionary layer = (lv.get_type() == Variant::DICTIONARY) ? (Dictionary)lv : Dictionary();
		layer_sig = hash_variant(layer_sig, layer.get("name", String()));
	}
	return to_i63(layer_sig);
}

void VoxelChecksums::_bind_methods() {
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("world_state_checksum", "chunks", "layers"), &VoxelChecksums::world_state_checksum);
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("chunk_state_checksum", "voxel_dict"), &VoxelChecksums::chunk_state_checksum);
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("entity_manager_checksum", "entities"), &VoxelChecksums::entity_manager_checksum);
	ClassDB::bind_static_method("VoxelChecksums", D_METHOD("layers_signature", "layers"), &VoxelChecksums::layers_signature);
}

