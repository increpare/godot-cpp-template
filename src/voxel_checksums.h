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
	// Returns non-negative 63-bit checksum (masked) to stay friendly with GDScript int.
	static int64_t world_state_checksum(const Dictionary &chunks, const Array &layers);
	static int64_t chunk_state_checksum(const Dictionary &voxel_dict);
	static int64_t entity_manager_checksum(const Array &entities);
	static int64_t layers_signature(const Array &layers);
};

} // namespace godot

