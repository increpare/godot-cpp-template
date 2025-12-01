#include "example_class.h"

void ExampleClass::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("print_type", "variant"), &ExampleClass::print_type);
	godot::ClassDB::bind_method(D_METHOD("print_array", "array"), &ExampleClass::print_array);
	godot::ClassDB::bind_method(D_METHOD("serialize_array", "array"), &ExampleClass::serialize_array);
}

void ExampleClass::print_type(const Variant &p_variant) const {
	print_line(vformat("Type: %d", p_variant.get_type()));
}

void ExampleClass::print_array(const TypedArray<Vector3i> &p_array) const {
	for (int i = 0; i < p_array.size(); i++) {
		print_line(vformat("Vector3i[%d]: %s", i, p_array[i]));
	}
}

PackedByteArray ExampleClass::serialize_array(const TypedArray<Vector3i> &p_array) const {
	PackedByteArray p_packed_array;
	for (int i = 0; i < p_array.size(); i++) {
		Vector3i v = p_array[i];
		p_packed_array.push_back(v.x);
		p_packed_array.push_back(v.y);
		p_packed_array.push_back(v.z);
	}
	return p_packed_array;
}