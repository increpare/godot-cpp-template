#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/classes/mesh.hpp"
#include "godot_cpp/classes/array_mesh.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "godot_cpp/variant/typed_array.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/packed_vector3_array.hpp"
#include "godot_cpp/variant/packed_int32_array.hpp"
#include "godot_cpp/variant/vector3i.hpp"
#include "godot_cpp/variant/vector3.hpp"

using namespace godot;

class OeufSerializer : public RefCounted {
	GDCLASS(OeufSerializer, RefCounted)

protected:
	static void _bind_methods();

public:
	OeufSerializer() = default;
	~OeufSerializer() override = default;

	void print_type(const Variant &p_variant) const;
	void print_array(const TypedArray<Vector3i> &p_array) const;
	PackedByteArray serialize_array(const TypedArray<Vector3i> &p_array) const;
	PackedByteArray serialize_game_data(const Array &p_savedat) const;
	Array deserialize_game_data(const PackedByteArray &p_buffer) const;
	Ref<Mesh> create_cube_mesh() const;
};
