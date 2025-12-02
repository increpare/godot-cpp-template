#include "oeuf_serializer.h"

void OeufSerializer::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("serialize_game_data", "savedat"), &OeufSerializer::serialize_game_data);
	godot::ClassDB::bind_method(D_METHOD("deserialize_game_data", "buffer"), &OeufSerializer::deserialize_game_data);
}


// Helper for writing to PackedByteArray
struct BufferWriter {
	PackedByteArray data;
	int offset = 0;

	void ensure_space(int p_bytes) {
		if (data.size() < offset + p_bytes) {
			int new_size = (data.size() == 0) ? 256 : data.size() * 2;
			while (new_size < offset + p_bytes) {
				new_size *= 2;
			}
			data.resize(new_size);
		}
	}

	void put_8(uint8_t p_value) {
		ensure_space(1);
		data.encode_u8(offset, p_value);
		offset += 1;
	}

	void put_16(int16_t p_value) {
		ensure_space(2);
		data.encode_s16(offset, p_value);
		offset += 2;
	}

	void put_32(int32_t p_value) {
		ensure_space(4);
		data.encode_s32(offset, p_value);
		offset += 4;
	}

	void put_float(float p_value) {
		ensure_space(4);
		data.encode_float(offset, p_value);
		offset += 4;
	}

	void put_utf8_string(const String &p_string) {
		PackedByteArray utf8 = p_string.to_utf8_buffer();
		int len = utf8.size();
		put_32(len);
		ensure_space(len);
		// Manual copy since we don't have append_array with direct offset control easily exposed without resizing exact
		const uint8_t *r = utf8.ptr();
		for (int i = 0; i < len; i++) {
			data.encode_u8(offset + i, r[i]);
		}
		offset += len;
	}

	PackedByteArray get_packed_byte_array() {
		data.resize(offset);
		return data;
	}
};

// Helper for reading from PackedByteArray
struct BufferReader {
	PackedByteArray data;
	int offset = 0;

	BufferReader(const PackedByteArray &p_data) : data(p_data) {}

	uint8_t get_8() {
		if (offset + 1 > data.size()) return 0;
		uint8_t v = data.decode_u8(offset);
		offset += 1;
		return v;
	}

	int16_t get_16() {
		if (offset + 2 > data.size()) return 0;
		int16_t v = data.decode_s16(offset);
		offset += 2;
		return v;
	}

	int32_t get_32() {
		if (offset + 4 > data.size()) return 0;
		int32_t v = data.decode_s32(offset);
		offset += 4;
		return v;
	}

	float get_float() {
		if (offset + 4 > data.size()) return 0.0f;
		float v = data.decode_float(offset);
		offset += 4;
		return v;
	}

	String get_utf8_string() {
		int32_t len = get_32();
		if (len < 0 || offset + len > data.size()) return "";
		
		// To decode utf8 string from a slice, we can use get_string_from_utf8 on a slice
		// Or construct a new PackedByteArray for the slice.
		// PackedByteArray slice(int64_t p_begin, int64_t p_end = 2147483647) const;
		PackedByteArray s = data.slice(offset, offset + len);
		offset += len;
		return s.get_string_from_utf8();
	}
};

PackedByteArray OeufSerializer::serialize_game_data(const Array &p_savedat) const {
	BufferWriter writer;

	// Structure of savedat:
	// ... (same comments as before)

	if (p_savedat.size() != 5) {
		ERR_PRINT(vformat("serialize_game_data: Invalid savedat array size (expected 5, got %d)", p_savedat.size()));
		return PackedByteArray();
	}

	// 0: level_state_data	
	Dictionary level_state_data = p_savedat[0];
	
	// version
	writer.put_8(level_state_data["version"]);

	// voxel_data
	Array voxel_data = level_state_data["voxel_data"];
	writer.put_32(voxel_data.size());

	Vector3i last_position = Vector3i(0, 0, 0);
	// DEBUG: Print voxel count
	// UtilityFunctions::print("Serialized voxel count: ", voxel_data.size());
	for (int i = 0; i < voxel_data.size(); i++) {
		Array voxel = voxel_data[i];
		Vector3i v = voxel[0];
		Vector3i delta = v - last_position;
		//if deltas all fit within a signed 8 bit int, we can use that
		if (delta.x >= -128 && delta.x <= 127 && delta.y >= -128 && delta.y <= 127 && delta.z >= -128 && delta.z <= 127) {
			writer.put_8(0);
			writer.put_8(delta.x);
			writer.put_8(delta.y);
			writer.put_8(delta.z);
		} else {
			writer.put_8(1);
			writer.put_16(v.x);
			writer.put_16(v.y);
			writer.put_16(v.z);
		}
		writer.put_8(voxel[1]); // blocktype
		writer.put_8(voxel[2]); // tx
		writer.put_8(voxel[3]); // ty
		//rot goes from 0 to 3, vflip is bool, so encode together
		int rot = voxel[4];
		int vflip = voxel[5] ? 1 : 0;
		writer.put_8(rot + vflip * 4); // combined rot (0-3) + vflip (0-1) * 4
		writer.put_8(voxel[6]);
	}

	// layers
	Array layers = level_state_data["layers"];
	writer.put_8(layers.size());
	for (int i = 0; i < layers.size(); i++) {
		Dictionary layer = layers[i];
		writer.put_utf8_string(layer["name"]);
		writer.put_8(layer["visible"]);
	}

	// selected_layer_idx
	writer.put_8(level_state_data["selected_layer_idx"]);

	// 1: camera_pos
	Vector3 camera_pos = p_savedat[1];
	writer.put_float(camera_pos.x);
	writer.put_float(camera_pos.y);
	writer.put_float(camera_pos.z);

	// 2: camera_base_rotation
	Vector3 camera_base_rotation = p_savedat[2];
	writer.put_float(camera_base_rotation.x);
	writer.put_float(camera_base_rotation.y);
	writer.put_float(camera_base_rotation.z);

	// 3: camera_rot_rotation
	Vector3 camera_rot_rotation = p_savedat[3];
	writer.put_float(camera_rot_rotation.x);
	writer.put_float(camera_rot_rotation.y);
	writer.put_float(camera_rot_rotation.z);

	// 4: entities
	Array entities = p_savedat[4];
	writer.put_16(entities.size());	

	for (int i = 0; i < entities.size(); i++) {
		Dictionary entity = entities[i];
		writer.put_utf8_string(entity["name"]);
		
		if (entity.has("type")) {
			writer.put_8(entity["type"]);
		} else {
			writer.put_8(0);
		}

		// Handle position type (Vector3 vs Vector3i)
		Vector3 pos;
		uint8_t pos_type = 0; // 0 = Vector3, 1 = Vector3i
		if (entity.has("position")) {
			Variant p = entity["position"];
			if (p.get_type() == Variant::VECTOR3I) {
				Vector3i pi = p;
				pos = Vector3(pi.x, pi.y, pi.z);
				pos_type = 1;
			} else {
				pos = p;
			}
		}
		writer.put_8(pos_type);
		writer.put_float(pos.x);
		writer.put_float(pos.y);
		writer.put_float(pos.z);
		
		if (entity.has("dir")) {
			writer.put_8(entity["dir"]);
		} else {
			writer.put_8(0);
		}

		if (entity.has("meta")) {
			writer.put_utf8_string(entity["meta"]);
		} else {
			writer.put_utf8_string("");
		}

		if (entity.has("asset_name")) {
			writer.put_utf8_string(entity["asset_name"]);
		} else {
			writer.put_utf8_string("");
		}

		if (entity.has("type") && (int)entity["type"] == 3) {
			Vector3i size_EDS = entity.has("size_EDS") ? (Vector3i)entity["size_EDS"] : Vector3i();
			writer.put_16(size_EDS.x);
			writer.put_16(size_EDS.y);
			writer.put_16(size_EDS.z);

			Vector3i size_WUN = entity.has("size_WUN") ? (Vector3i)entity["size_WUN"] : Vector3i();
			writer.put_16(size_WUN.x);
			writer.put_16(size_WUN.y);
			writer.put_16(size_WUN.z);
		}
	}

	return writer.get_packed_byte_array();
}

Array OeufSerializer::deserialize_game_data(const PackedByteArray &p_buffer) const {
	BufferReader reader(p_buffer);

	// Root array
	Array savedat;
	
	// 0: level_state_data (Dictionary)
	Dictionary level_state_data;
	
	// version
	level_state_data[StringName("version")] = reader.get_8();
	
	// voxel_data
	TypedArray<Array> voxel_data;
	int voxel_count = reader.get_32();
	UtilityFunctions::print("Deserializing voxel_data, count: ", voxel_count);
	
	// We want to reconstruct typed array if possible, or at least match input structure.
	// minimal.txt had Array[Array].
	
	Vector3i last_position = Vector3i(0, 0, 0);
	for (int i = 0; i < voxel_count; i++) {
		Array voxel;
		uint8_t position_type = reader.get_8();
		if (position_type == 0) {
			last_position += Vector3i(reader.get_8(), reader.get_8(), reader.get_8());
		} else {
			last_position = Vector3i(reader.get_16(), reader.get_16(), reader.get_16());
		}

		voxel.append(last_position);
		
		voxel.append(reader.get_8()); // blocktype
		voxel.append(reader.get_8()); // tx
		voxel.append(reader.get_8()); // ty
		uint8_t rot_vflip = reader.get_8();
		voxel.append(rot_vflip & 3); // rot (bits 0-1)
		voxel.append((rot_vflip & 4) != 0);  // vflip (bit 2)
		voxel.append(reader.get_8()); // extra int
		
		voxel_data.append(voxel);
	}
	level_state_data[StringName("voxel_data")] = voxel_data;
	
	// layers
	Array layers;
	int layers_count = reader.get_8();
	UtilityFunctions::print("Deserializing layers, count: ", layers_count);
	for (int i = 0; i < layers_count; i++) {
		Dictionary layer;
		layer[StringName("name")] = reader.get_utf8_string();
		layer[StringName("visible")] = reader.get_8() != 0;
		layers.append(layer);
	}
	level_state_data[StringName("layers")] = layers;
	
	// selected_layer_idx
	level_state_data[StringName("selected_layer_idx")] = reader.get_8();
	
	savedat.append(level_state_data);
	
	// 1: camera_pos
	Vector3 camera_pos;
	camera_pos.x = reader.get_float();
	camera_pos.y = reader.get_float();
	camera_pos.z = reader.get_float();
	savedat.append(camera_pos);
	
	// 2: camera_base_rotation
	Vector3 camera_base_rotation;
	camera_base_rotation.x = reader.get_float();
	camera_base_rotation.y = reader.get_float();
	camera_base_rotation.z = reader.get_float();
	savedat.append(camera_base_rotation);
	
	// 3: camera_rot_rotation
	Vector3 camera_rot_rotation;
	camera_rot_rotation.x = reader.get_float();
	camera_rot_rotation.y = reader.get_float();
	camera_rot_rotation.z = reader.get_float();
	savedat.append(camera_rot_rotation);
	
	// 4: entities
	TypedArray<Dictionary> entities;
	int entities_count = reader.get_16();
	UtilityFunctions::print("Deserializing entities, count: ", entities_count);
	for (int i = 0; i < entities_count; i++) {
		Dictionary entity;
		entity[StringName("name")] = reader.get_utf8_string();
		entity[StringName("type")] = reader.get_8();
		
		uint8_t pos_type = reader.get_8();
		Vector3 pos;
		pos.x = reader.get_float();
		pos.y = reader.get_float();
		pos.z = reader.get_float();
		
		if (pos_type == 1) {
			entity[StringName("position")] = Vector3i(pos.x, pos.y, pos.z);
		} else {
			entity[StringName("position")] = pos;
		}
		
		int dir = reader.get_8();
		if (dir != 0 || (int)entity[StringName("type")] != 3) {
			entity[StringName("dir")] = dir;
		}
		entity[StringName("meta")] = reader.get_utf8_string();
		
		String asset_name = reader.get_utf8_string();
		if (!asset_name.is_empty()) {
			entity[StringName("asset_name")] = asset_name;
		}
		
		if ((int)entity[StringName("type")] == 3) {
			Vector3i size_EDS;
			size_EDS.x = reader.get_16();
			size_EDS.y = reader.get_16();
			size_EDS.z = reader.get_16();
			entity[StringName("size_EDS")] = size_EDS;

			Vector3i size_WUN;
			size_WUN.x = reader.get_16();
			size_WUN.y = reader.get_16();
			size_WUN.z = reader.get_16();
			entity[StringName("size_WUN")] = size_WUN;
		}

		entities.append(entity);
	}
	savedat.append(entities);

	return savedat;
}
