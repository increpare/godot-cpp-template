#pragma once

#include "godot_cpp/classes/ref_counted.hpp"
#include "godot_cpp/classes/wrapped.hpp"
#include "godot_cpp/variant/variant.hpp"
#include "godot_cpp/variant/typed_array.hpp"
#include "godot_cpp/variant/packed_byte_array.hpp"
#include "godot_cpp/variant/vector3i.hpp"

using namespace godot;

class ExampleClass : public RefCounted {
	GDCLASS(ExampleClass, RefCounted)

protected:
	static void _bind_methods();

public:
	ExampleClass() = default;
	~ExampleClass() override = default;

	void print_type(const Variant &p_variant) const;
	void print_array(const TypedArray<Vector3i> &p_array) const;
	PackedByteArray serialize_array(const TypedArray<Vector3i> &p_array) const;
};
