#include "example_class.h"
#include <cstring>
#include <string>
#include <string_view>
#include <cstdio>
#include <charconv>
#include "godot_cpp/classes/marshalls.hpp"

void OeufSerializer::_bind_methods() {
	godot::ClassDB::bind_method(D_METHOD("print_type", "variant"), &OeufSerializer::print_type);
	godot::ClassDB::bind_method(D_METHOD("print_array", "array"), &OeufSerializer::print_array);
	godot::ClassDB::bind_method(D_METHOD("serialize_array", "array"), &OeufSerializer::serialize_array);
	godot::ClassDB::bind_method(D_METHOD("serialize_game_data", "savedat"), &OeufSerializer::serialize_game_data);
	godot::ClassDB::bind_method(D_METHOD("deserialize_game_data", "buffer"), &OeufSerializer::deserialize_game_data);
	godot::ClassDB::bind_method(D_METHOD("serialize_to_string", "savedat"), &OeufSerializer::serialize_to_string);
	godot::ClassDB::bind_method(D_METHOD("deserialize_from_string", "string"), &OeufSerializer::deserialize_from_string);
	godot::ClassDB::bind_method(D_METHOD("create_cube_mesh"), &OeufSerializer::create_cube_mesh);
}

void OeufSerializer::print_type(const Variant &p_variant) const {
	print_line(vformat("Type: %d", p_variant.get_type()));
}

void OeufSerializer::print_array(const TypedArray<Vector3i> &p_array) const {
	for (int i = 0; i < p_array.size(); i++) {
		print_line(vformat("Vector3i[%d]: %s", i, p_array[i]));
	}
}

PackedByteArray OeufSerializer::serialize_array(const TypedArray<Vector3i> &p_array) const {
	int count = p_array.size();
	PackedByteArray p_packed_array;
	p_packed_array.resize(count * 3); // Pre-allocate exact size
	
	uint8_t *data_ptr = p_packed_array.ptrw();
	for (int i = 0; i < count; i++) {
		Vector3i v = p_array[i];
		int base = i * 3;
		data_ptr[base] = static_cast<uint8_t>(v.x);
		data_ptr[base + 1] = static_cast<uint8_t>(v.y);
		data_ptr[base + 2] = static_cast<uint8_t>(v.z);
	}
	return p_packed_array;
}

// Helper for writing to PackedByteArray
struct BufferWriter {
	PackedByteArray data;
	int offset = 0;

	void ensure_space(int p_bytes) {
		int needed = offset + p_bytes;
		int current_size = data.size();
		if (current_size < needed) {
			// Grow more aggressively - at least 2x or to needed size
			int new_size = current_size == 0 ? 512 : current_size * 2;
			if (new_size < needed) {
				new_size = needed + (needed / 4); // Add 25% headroom
			}
			data.resize(new_size);
		}
	}

	// Pre-allocate buffer with estimated size to reduce reallocations
	void reserve(int p_estimated_size) {
		if (p_estimated_size > 0 && data.size() < p_estimated_size) {
			data.resize(p_estimated_size);
		}
	}

	void put_8(uint8_t p_value) {
		ensure_space(1);
		data.encode_u8(offset, p_value);
		offset += 1;
	}

	void put_s8(int8_t p_value) {
		ensure_space(1);
		// Cast to uint8_t to preserve bit pattern for negative values
		data.encode_u8(offset, static_cast<uint8_t>(p_value));
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
		if (len > 0) {
			ensure_space(len);
			// Use direct memory copy for better performance
			const uint8_t *src = utf8.ptr();
			uint8_t *dst = data.ptrw() + offset;
			memcpy(dst, src, len);
			offset += len;
		}
	}

	// Optimized method to write raw bytes directly
	void put_bytes(const uint8_t *p_bytes, int p_len) {
		if (p_len > 0) {
			ensure_space(p_len);
			uint8_t *dst = data.ptrw() + offset;
			memcpy(dst, p_bytes, p_len);
			offset += p_len;
		}
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

	int8_t get_s8() {
		if (offset + 1 > data.size()) return 0;
		uint8_t v = data.decode_u8(offset);
		offset += 1;
		// Cast back to signed to interpret as two's complement
		return static_cast<int8_t>(v);
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

// Helper for writing human-readable text
struct TextWriter {
	std::string s;
	bool first_in_line = true;

	static char *_append_int_chars(char *p_dst, int64_t p_value) {
		auto [ptr, ec] = std::to_chars(p_dst, p_dst + 24, p_value);
		if (ec != std::errc()) {
			return p_dst;
		}
		return ptr;
	}

	void reserve(size_t p_size) {
		s.reserve(p_size);
	}

	void _put_space() {
		if (!first_in_line) {
			s += ' ';
		}
		first_in_line = false;
	}

	void put_tag(const char *p_tag) {
		_put_space();
		s += p_tag;
	}

	void put_tag(const String &p_tag) {
		_put_space();
		s += p_tag.utf8().get_data();
	}

	void put_int(int64_t p_value) {
		_put_space();
		if (p_value >= 0 && p_value < 10) {
			s += (char)('0' + p_value);
		} else {
			char buf[24];
			auto [ptr, ec] = std::to_chars(buf, buf + sizeof(buf), p_value);
			s.append(buf, ptr - buf);
		}
	}

	void put_voxel_line(bool p_is_delta, const Vector3i &p_pos, int64_t p_blocktype, int64_t p_tx, int64_t p_ty, int64_t p_rot_vflip, int64_t p_extra) {
		char buf[192];
		char *p = buf;
		// Format: vx <type> <x> <y> <z> <blocktype> <tx> <ty> <rot_vflip> <extra>\n
		*p++ = 'v';
		*p++ = 'x';
		*p++ = ' ';
		*p++ = p_is_delta ? '0' : '1';
		*p++ = ' ';
		p = _append_int_chars(p, p_pos.x);
		*p++ = ' ';
		p = _append_int_chars(p, p_pos.y);
		*p++ = ' ';
		p = _append_int_chars(p, p_pos.z);
		*p++ = ' ';
		p = _append_int_chars(p, p_blocktype);
		*p++ = ' ';
		p = _append_int_chars(p, p_tx);
		*p++ = ' ';
		p = _append_int_chars(p, p_ty);
		*p++ = ' ';
		p = _append_int_chars(p, p_rot_vflip);
		*p++ = ' ';
		p = _append_int_chars(p, p_extra);
		*p++ = '\n';
		s.append(buf, p - buf);
		first_in_line = true;
	}

	void put_u8(uint8_t p_value) {
		// Human-readable levels are tokenized whitespace-separated; u8 fits in normal int formatting.
		put_int((int64_t)p_value);
	}

	void put_float(double p_value) {
		_put_space();
		char buf[32];
		int len = snprintf(buf, sizeof(buf), "%g", p_value);
		s.append(buf, len);
	}

	void put_string(const String &p_string) {
		_put_space();
		s += '"';
		s += p_string.c_escape().utf8().get_data();
		s += '"';
	}

	void put_vector3i(const Vector3i &p_vec) {
		put_int(p_vec.x);
		put_int(p_vec.y);
		put_int(p_vec.z);
	}

	void put_vector3(const Vector3 &p_vec) {
		put_float(p_vec.x);
		put_float(p_vec.y);
		put_float(p_vec.z);
	}

	void end_line() {
		s += '\n';
		first_in_line = true;
	}

	String get_string() const {
		return String::utf8(s.data(), s.size());
	}
};

// Helper for reading human-readable text
struct TextReaderTokenized {
	PackedStringArray lines;
	int line_idx = 0;

	TextReaderTokenized(const String &p_text) {
		lines = p_text.split("\n", false);
	}

	bool has_more_lines() const {
		return line_idx < lines.size();
	}

	struct LineTokenizer {
		String line;
		int pos = 0;

		LineTokenizer(const String &p_line) : line(p_line) {}

		String next_token() {
			while (pos < line.length() && line[pos] <= ' ') {
				pos++;
			}
			if (pos >= line.length()) {
				return "";
			}

			if (line[pos] == '"') {
				pos++;
				int start = pos;
				while (pos < line.length() && line[pos] != '"') {
					if (line[pos] == '\\' && pos + 1 < line.length()) {
						pos++;
					}
					pos++;
				}
				String s = line.substr(start, pos - start);
				if (pos < line.length()) {
					pos++; // skip closing quote
				}
				return s.c_unescape();
			} else {
				int start = pos;
				while (pos < line.length() && line[pos] > ' ') {
					pos++;
				}
				return line.substr(start, pos - start);
			}
		}

		int64_t next_int() {
			return next_token().to_int();
		}

		uint8_t next_u8() {
			int64_t v = next_int();
			if (v < 0) {
				return 0;
			}
			if (v > 255) {
				return 255;
			}
			return (uint8_t)v;
		}

		double next_float() {
			return next_token().to_float();
		}

		Vector3i next_vector3i() {
			int64_t x = next_int();
			int64_t y = next_int();
			int64_t z = next_int();
			return Vector3i(x, y, z);
		}

		Vector3 next_vector3() {
			double x = next_float();
			double y = next_float();
			double z = next_float();
			return Vector3(x, y, z);
		}
	};

	LineTokenizer next_line() {
		if (has_more_lines()) {
			return LineTokenizer(lines[line_idx++]);
		}
		return LineTokenizer("");
	}
};

// Streaming tokenizer that avoids splitting the full text into line Strings.
struct StreamingTextTokenizer {
	CharString utf8;
	const char *ptr = nullptr;
	const char *end = nullptr;

	explicit StreamingTextTokenizer(const String &p_text) {
		utf8 = p_text.utf8();
		ptr = utf8.get_data();
		end = ptr + utf8.length();
	}

	bool has_more_tokens() {
		skip_whitespace();
		return ptr < end;
	}

	void skip_whitespace() {
		while (ptr < end && static_cast<unsigned char>(*ptr) <= ' ') {
			ptr++;
		}
	}

	static bool is_line_break(char p_char) {
		return p_char == '\n' || p_char == '\r';
	}

	int remaining_token_count() const {
		const char *p = ptr;
		int count = 0;
		while (p < end) {
			while (p < end && !is_line_break(*p) && static_cast<unsigned char>(*p) <= ' ') {
				p++;
			}
			if (p >= end || is_line_break(*p)) {
				break;
			}

			count++;
			if (*p == '"') {
				p++;
				while (p < end && !is_line_break(*p) && *p != '"') {
					if (*p == '\\' && p + 1 < end && !is_line_break(*(p + 1))) {
						p++;
					}
					p++;
				}
				if (p < end && *p == '"') {
					p++;
				}
			} else {
				while (p < end && static_cast<unsigned char>(*p) > ' ') {
					p++;
				}
			}
		}
		return count;
	}

	bool next_raw_token(std::string_view &r_token) {
		skip_whitespace();
		if (ptr >= end) {
			r_token = std::string_view();
			return false;
		}
		const char *start = ptr;
		while (ptr < end && static_cast<unsigned char>(*ptr) > ' ') {
			ptr++;
		}
		r_token = std::string_view(start, static_cast<size_t>(ptr - start));
		return true;
	}

	int64_t next_int() {
		std::string_view token;
		if (!next_raw_token(token) || token.empty()) {
			return 0;
		}
		int64_t value = 0;
		auto [pos, ec] = std::from_chars(token.data(), token.data() + token.size(), value);
		if (ec != std::errc() || pos != token.data() + token.size()) {
			return String::utf8(token.data(), (int)token.size()).to_int();
		}
		return value;
	}

	double next_float() {
		std::string_view token;
		if (!next_raw_token(token) || token.empty()) {
			return 0.0;
		}
		return String::utf8(token.data(), (int)token.size()).to_float();
	}

	Vector3i next_vector3i() {
		int64_t x = next_int();
		int64_t y = next_int();
		int64_t z = next_int();
		return Vector3i(x, y, z);
	}

	Vector3 next_vector3() {
		double x = next_float();
		double y = next_float();
		double z = next_float();
		return Vector3(x, y, z);
	}

	uint8_t next_u8() {
		int64_t v = next_int();
		if (v < 0) {
			return 0;
		}
		if (v > 255) {
			return 255;
		}
		return (uint8_t)v;
	}

	String next_token() {
		skip_whitespace();
		if (ptr >= end) {
			return "";
		}

		if (*ptr == '"') {
			ptr++;
			const char *start = ptr;
			while (ptr < end && *ptr != '"') {
				if (*ptr == '\\' && ptr + 1 < end) {
					ptr++;
				}
				ptr++;
			}
			String s = String::utf8(start, (int)(ptr - start)).c_unescape();
			if (ptr < end && *ptr == '"') {
				ptr++;
			}
			return s;
		}

		std::string_view token;
		if (!next_raw_token(token)) {
			return "";
		}
		return String::utf8(token.data(), (int)token.size());
	}
};

PackedByteArray OeufSerializer::serialize_game_data(const Array &p_savedat) const {
	if (p_savedat.size() != 5) {
		ERR_PRINT(vformat("serialize_game_data: Invalid savedat array size (expected 5, got %d)", p_savedat.size()));
		return PackedByteArray();
	}

	// 0: level_state_data
	Dictionary level_state_data = p_savedat[0];
	
	// 4: entities - support both legacy (array) and versioned (dict with "version" + "entities")
	Variant entities_slot = p_savedat[4];
	int entities_version = 0;
	Array entities;
	if (entities_slot.get_type() == Variant::DICTIONARY) {
		Dictionary d = entities_slot;
		entities_version = d["version"];
		entities = d["entities"];
	} else {
		entities = entities_slot;
	}
	
	// Estimate buffer size: version (1) + voxel_count (4) + entities_count (2) + rough estimates
	Array voxel_data = level_state_data["voxel_data"];
	int voxel_count = voxel_data.size();
	int entities_count = entities.size();
	
	// Rough estimate: ~10 bytes per voxel, ~50 bytes per entity, plus overhead
	int estimated_size = 64 + (voxel_count * 10) + (entities_count * 50);
	
	BufferWriter writer;
	writer.reserve(estimated_size);
	
	// version
	writer.put_8(level_state_data["version"]);

	// voxel_data
	writer.put_32(voxel_count);

	Vector3i last_position = Vector3i(0, 0, 0);
	for (int i = 0; i < voxel_count; i++) {
		Array voxel = voxel_data[i];
		Vector3i v = voxel[0];
		Vector3i delta = v - last_position;
		//if deltas all fit within a signed 8 bit int, we can use that
		if (delta.x >= -128 && delta.x <= 127 && delta.y >= -128 && delta.y <= 127 && delta.z >= -128 && delta.z <= 127) {
			writer.put_8(0);
			writer.put_s8(static_cast<int8_t>(delta.x));
			writer.put_s8(static_cast<int8_t>(delta.y));
			writer.put_s8(static_cast<int8_t>(delta.z));
		} else {
			writer.put_8(1);
			writer.put_16(v.x);
			writer.put_16(v.y);
			writer.put_16(v.z);
		}
		last_position = v;
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
	int layers_count = layers.size();
	writer.put_8(layers_count);
	for (int i = 0; i < layers_count; i++) {
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

	// 4: entities (version byte, then count)
	// Note: entities_version byte was added in this format; old binary files are not compatible.
	writer.put_8(entities_version);
	writer.put_16(entities_count);
	for (int i = 0; i < entities_count; i++) {
		Dictionary entity = entities[i];
		writer.put_utf8_string(entity["name"]);
		
		int32_t entity_type = entity["type"];
		writer.put_8(entity_type);

		// Handle position type (Vector3 vs Vector3i)
		Vector3i pos = entity["position"];		
		writer.put_16(pos.x);
		writer.put_16(pos.y);
		writer.put_16(pos.z);

		uint8_t layer = entity.has("layer") ? (uint8_t)(int)entity["layer"] : 0;
		writer.put_8(layer);
		
		// Calculate flags for optional fields first to save space
		uint8_t flags = 0;
		String meta_str;
		String asset_name_str;
		String placed_user_id_str;
		String placed_user_display_name_str;
		String edited_user_id_str;
		String edited_user_display_name_str;
		int32_t dir_value = 0;
		int32_t star_colour_idx = 0;
		
		if (entity.has("dir")) {
			dir_value = entity["dir"];
			flags |= 0x01; // bit 0: has dir
		}
		
		if (entity.has("meta")) {
			meta_str = entity["meta"];
			if (!meta_str.is_empty()) {
				flags |= 0x02; // bit 1: has non-empty meta
			}
		}
		
		if (entity.has("asset_name")) {
			asset_name_str = entity["asset_name"];
			if (!asset_name_str.is_empty()) {
				flags |= 0x04; // bit 2: has non-empty asset_name
			}
		}

		// bit 3: has star colour palette index (ROYGBIV)
		if (entities_version >= 5) {
			if (entity.has("colour") && ((Variant)entity["colour"]).get_type() == Variant::INT) {
				star_colour_idx = entity["colour"];
				flags |= 0x08;
			}
		}

		if (entities_version >= 6) {
			placed_user_id_str = entity.get("placed_user_id", String());
			placed_user_display_name_str = entity.get("placed_user_display_name", String());
			edited_user_id_str = entity.get("edited_user_id", String());
			edited_user_display_name_str = entity.get("edited_user_display_name", String());
		}
		
		// Write flags byte, then conditional fields
		writer.put_8(flags);
		
		if ((flags & 0x01) != 0) {
			writer.put_8(static_cast<uint8_t>(dir_value + 1));
		}
		
		if ((flags & 0x02) != 0) {
			writer.put_utf8_string(meta_str);
		}

		if ((flags & 0x04) != 0) {
			writer.put_utf8_string(asset_name_str);
		}

		if ((flags & 0x08) != 0) {
			// palette index (0..N-1)
			writer.put_8(static_cast<uint8_t>(star_colour_idx));
		}

		if (entities_version >= 6) {
			writer.put_utf8_string(placed_user_id_str);
			writer.put_utf8_string(placed_user_display_name_str);
			writer.put_utf8_string(edited_user_id_str);
			writer.put_utf8_string(edited_user_display_name_str);
		}

		if (entity_type == 3) {
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
	Vector3i last_position = Vector3i(0, 0, 0);
	for (int i = 0; i < voxel_count; i++) {
		Array voxel;
		uint8_t position_type = reader.get_8();
		if (position_type == 0) {
			last_position += Vector3i(reader.get_s8(), reader.get_s8(), reader.get_s8());
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
	
	// 4: entities (version byte, then count)
	int entities_version = reader.get_8();
	int entities_count = reader.get_16();
	TypedArray<Dictionary> entities;
	for (int i = 0; i < entities_count; i++) {
		Dictionary entity;
		entity[StringName("name")] = reader.get_utf8_string();
		int32_t entity_type = reader.get_8();
		entity[StringName("type")] = entity_type;

		Vector3i pos;
		pos.x = reader.get_16();
		pos.y = reader.get_16();
		pos.z = reader.get_16();
		entity[StringName("position")] = pos;
		
		if (entities_version >= 3){
			entity[StringName("layer")] = reader.get_8();
		} else {
			entity[StringName("layer")] = 0;
		}
		
		// Read flags byte for optional fields
		uint8_t flags = reader.get_8();
		
		if ((flags & 0x01) != 0) {
			// Has dir
			int dir = reader.get_8();
			entity[StringName("dir")] = dir - 1;
		}
		
		if ((flags & 0x02) != 0) {
			// Has non-empty meta
			entity[StringName("meta")] = reader.get_utf8_string();
		}
		
		if ((flags & 0x04) != 0) {
			// Has non-empty asset_name
			entity[StringName("asset_name")] = reader.get_utf8_string();
		}

		if ((flags & 0x08) != 0) {
			entity[StringName("colour")] = (int32_t)reader.get_8();
		}

		if (entities_version >= 6) {
			entity[StringName("placed_user_id")] = reader.get_utf8_string();
			entity[StringName("placed_user_display_name")] = reader.get_utf8_string();
			entity[StringName("edited_user_id")] = reader.get_utf8_string();
			entity[StringName("edited_user_display_name")] = reader.get_utf8_string();
		}

		if (entity_type == 3) {
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
	Dictionary entities_dict;
	entities_dict[StringName("version")] = entities_version;
	entities_dict[StringName("entities")] = entities;
	savedat.append(entities_dict);

	return savedat;
}

String OeufSerializer::serialize_to_string(const Array &p_savedat) const {
	static const StringName SN_VERSION("version");
	static const StringName SN_VOXEL_DATA("voxel_data");
	static const StringName SN_LAYERS("layers");
	static const StringName SN_SELECTED_LAYER_IDX("selected_layer_idx");
	static const StringName SN_ENTITIES("entities");
	static const StringName SN_NAME("name");
	static const StringName SN_VISIBLE("visible");
	static const StringName SN_TYPE("type");
	static const StringName SN_POSITION("position");
	static const StringName SN_LAYER("layer");
	static const StringName SN_DIR("dir");
	static const StringName SN_META("meta");
	static const StringName SN_ASSET_NAME("asset_name");
	static const StringName SN_COLOUR("colour");
	static const StringName SN_SIZE_EDS("size_EDS");
	static const StringName SN_SIZE_WUN("size_WUN");
	static const StringName SN_PLACED_USER_ID("placed_user_id");
	static const StringName SN_PLACED_USER_DISPLAY_NAME("placed_user_display_name");
	static const StringName SN_EDITED_USER_ID("edited_user_id");
	static const StringName SN_EDITED_USER_DISPLAY_NAME("edited_user_display_name");

	if (p_savedat.size() != 5) {
		ERR_PRINT(vformat("serialize_to_string: Invalid savedat array size (expected 5, got %d)", p_savedat.size()));
		return "";
	}

	Dictionary level_state_data = p_savedat[0];
	Array voxel_data = level_state_data[SN_VOXEL_DATA];
	Array layers = level_state_data[SN_LAYERS];
	// entities - support both legacy (array) and versioned (dict with "version" + "entities")
	Variant entities_slot = p_savedat[4];
	int entities_version = 0;
	Array entities;
	if (entities_slot.get_type() == Variant::DICTIONARY) {
		Dictionary d = entities_slot;
		entities_version = d[SN_VERSION];
		entities = d[SN_ENTITIES];
	} else {
		entities = entities_slot;
	}

	TextWriter writer;

	int voxel_count = voxel_data.size();
	int entities_count = entities.size();
	int layers_count = layers.size();

	// Rough estimate: ~40 bytes per voxel, ~100 per entity, plus overhead
	size_t estimated_size = 1024 + (voxel_count * 40) + (entities_count * 100);
	writer.reserve(estimated_size);

	// version
	writer.put_tag("version");
	writer.put_int(level_state_data[SN_VERSION]);
	writer.end_line();

	// voxel_data
	writer.put_tag("voxels");
	writer.put_int(voxel_count);
	writer.end_line();

	Vector3i last_position = Vector3i(0, 0, 0);
	for (int i = 0; i < voxel_count; i++) {
		Array voxel = voxel_data[i];
		Vector3i v = voxel[0];
		Vector3i delta = v - last_position;
		const bool is_delta = (delta.x >= -128 && delta.x <= 127 && delta.y >= -128 && delta.y <= 127 && delta.z >= -128 && delta.z <= 127);
		const Vector3i pos_to_write = is_delta ? delta : v;
		last_position = v;

		int rot = voxel[4];
		int vflip = (bool)voxel[5] ? 1 : 0;
		writer.put_voxel_line(
			is_delta,
			pos_to_write,
			(int64_t)voxel[1], // blocktype
			(int64_t)voxel[2], // tx
			(int64_t)voxel[3], // ty
			(int64_t)(rot + vflip * 4),
			(int64_t)voxel[6] // extra
		);
	}

	// layers
	writer.put_tag("layers");
	writer.put_int(layers_count);
	writer.end_line();
	for (int i = 0; i < layers_count; i++) {
		Dictionary layer = layers[i];
		writer.put_tag("l");
		writer.put_string(layer[SN_NAME]);
		writer.put_int((bool)layer[SN_VISIBLE] ? 1 : 0);
		writer.end_line();
	}

	// selected_layer_idx
	writer.put_tag("selected");
	writer.put_int(level_state_data[SN_SELECTED_LAYER_IDX]);
	writer.end_line();

	// camera
	writer.put_tag("cp");
	writer.put_vector3(p_savedat[1]);
	writer.end_line();

	writer.put_tag("cbr");
	writer.put_vector3(p_savedat[2]);
	writer.end_line();

	writer.put_tag("crr");
	writer.put_vector3(p_savedat[3]);
	writer.end_line();

	// entities (version, then count)
	writer.put_tag("entities_version");
	writer.put_int(entities_version);
	writer.end_line();
	writer.put_tag("entities");
	writer.put_int(entities_count);
	writer.end_line();

	for (int i = 0; i < entities_count; i++) {
		Dictionary entity = entities[i];
		writer.put_tag("e");
		writer.put_string(entity[SN_NAME]);
		
		int32_t entity_type = entity[SN_TYPE];
		writer.put_int(entity_type);
		writer.put_vector3i(entity[SN_POSITION]);

		writer.put_int(entity[SN_LAYER]);
		
		uint8_t flags = 0;
		String meta_str;
		String asset_name_str;
		String placed_user_id_str;
		String placed_user_display_name_str;
		String edited_user_id_str;
		String edited_user_display_name_str;
		int32_t dir_value = 0;
		int32_t star_colour_idx = 0;
		
		if (entity.has(SN_DIR)) {
			dir_value = entity[SN_DIR];
			flags |= 0x01;
		}
		if (entity.has(SN_META)) {
			meta_str = entity[SN_META];
			if (!meta_str.is_empty()) flags |= 0x02;
		}
		if (entity.has(SN_ASSET_NAME)) {
			asset_name_str = entity[SN_ASSET_NAME];
			if (!asset_name_str.is_empty()) flags |= 0x04;
		}
		if (entities_version >= 5) {
			if (entity.has(SN_COLOUR) && ((Variant)entity[SN_COLOUR]).get_type() == Variant::INT) {
				star_colour_idx = entity[SN_COLOUR];
				flags |= 0x08;
			}
		}
		if (entities_version >= 6) {
			placed_user_id_str = entity.get(SN_PLACED_USER_ID, String());
			placed_user_display_name_str = entity.get(SN_PLACED_USER_DISPLAY_NAME, String());
			edited_user_id_str = entity.get(SN_EDITED_USER_ID, String());
			edited_user_display_name_str = entity.get(SN_EDITED_USER_DISPLAY_NAME, String());
		}
		
		writer.put_int(flags);
		if (flags & 0x01) writer.put_int(dir_value + 1);
		if (flags & 0x02) writer.put_string(meta_str);
		if (flags & 0x04) writer.put_string(asset_name_str);
		if (flags & 0x08) {
			// Star palette index (ROYGBIV): 0..6 today, but keep wire as u8 for forward-compat.
			int64_t idx = star_colour_idx;
			if (idx < 0) {
				idx = 0;
			}
			if (idx > 255) {
				idx = 255;
			}
			writer.put_u8((uint8_t)idx);
		}
		if (entities_version >= 6) {
			writer.put_string(placed_user_id_str);
			writer.put_string(placed_user_display_name_str);
			writer.put_string(edited_user_id_str);
			writer.put_string(edited_user_display_name_str);
		}

		if (entity_type == 3) {
			Vector3i size_EDS = entity.has(SN_SIZE_EDS) ? (Vector3i)entity[SN_SIZE_EDS] : Vector3i();
			writer.put_vector3i(size_EDS);
			Vector3i size_WUN = entity.has(SN_SIZE_WUN) ? (Vector3i)entity[SN_SIZE_WUN] : Vector3i();
			writer.put_vector3i(size_WUN);
		}
		writer.end_line();
	}

	return writer.get_string();
}

Array OeufSerializer::deserialize_from_string(const godot::String &p_string) const {
	static const StringName SN_VERSION("version");
	static const StringName SN_VOXEL_DATA("voxel_data");
	static const StringName SN_LAYERS("layers");
	static const StringName SN_SELECTED_LAYER_IDX("selected_layer_idx");
	static const StringName SN_ENTITIES("entities");
	static const StringName SN_NAME("name");
	static const StringName SN_VISIBLE("visible");
	static const StringName SN_TYPE("type");
	static const StringName SN_POSITION("position");
	static const StringName SN_LAYER("layer");
	static const StringName SN_DIR("dir");
	static const StringName SN_META("meta");
	static const StringName SN_ASSET_NAME("asset_name");
	static const StringName SN_COLOUR("colour");
	static const StringName SN_SIZE_EDS("size_EDS");
	static const StringName SN_SIZE_WUN("size_WUN");
	static const StringName SN_PLACED_USER_ID("placed_user_id");
	static const StringName SN_PLACED_USER_DISPLAY_NAME("placed_user_display_name");
	static const StringName SN_EDITED_USER_ID("edited_user_id");
	static const StringName SN_EDITED_USER_DISPLAY_NAME("edited_user_display_name");

	StreamingTextTokenizer reader(p_string);
	Array savedat;
	Dictionary level_state_data;
	TypedArray<Array> voxel_data;
	Array layers;
	TypedArray<Dictionary> entities;
	int entities_version = 0;
	int voxel_write_idx = 0;
	int layer_write_idx = 0;
	int entity_write_idx = 0;
	bool voxel_presized = false;
	bool layer_presized = false;
	bool entity_presized = false;
	
	Vector3 camera_pos;
	Vector3 camera_base_rotation;
	Vector3 camera_rot_rotation;
	
	Vector3i last_position = Vector3i(0, 0, 0);

	while (reader.has_more_tokens()) {
		std::string_view tag_sv;
		if (!reader.next_raw_token(tag_sv) || tag_sv.empty()) {
			continue;
		}

		if (tag_sv == "version") {
			level_state_data[SN_VERSION] = reader.next_int();
		} else if (tag_sv == "voxels") {
			int expected_voxels = reader.next_int();
			if (expected_voxels > 0) {
				voxel_data.resize(expected_voxels);
				voxel_presized = true;
			}
		} else if (tag_sv == "entities_version") {
			entities_version = reader.next_int();
		} else if (tag_sv == "entities") {
			int expected_entities = reader.next_int(); // entities are still parsed from "e" tags.
			if (expected_entities > 0) {
				entities.resize(expected_entities);
				entity_presized = true;
			}
		} else if (tag_sv == "vx") {
			Array voxel;
			voxel.resize(7);
			int type = reader.next_int();
			if (type == 0) {
				last_position += reader.next_vector3i();
			} else {
				last_position = reader.next_vector3i();
			}
			voxel[0] = last_position;
			voxel[1] = reader.next_int(); // blocktype
			voxel[2] = reader.next_int(); // tx
			voxel[3] = reader.next_int(); // ty
			int rot_vflip = reader.next_int();
			voxel[4] = rot_vflip & 3;
			voxel[5] = (rot_vflip & 4) != 0;
			voxel[6] = reader.next_int(); // extra
			if (voxel_presized && voxel_write_idx < voxel_data.size()) {
				voxel_data.set(voxel_write_idx, voxel);
				voxel_write_idx++;
			} else {
				voxel_data.append(voxel);
			}
		} else if (tag_sv == "l") {
			Dictionary layer;
			layer[SN_NAME] = reader.next_token();
			layer[SN_VISIBLE] = reader.next_int() != 0;
			if (layer_presized && layer_write_idx < layers.size()) {
				layers[layer_write_idx] = layer;
				layer_write_idx++;
			} else {
				layers.append(layer);
			}
		} else if (tag_sv == "layers") {
			int expected_layers = reader.next_int();
			if (expected_layers > 0) {
				layers.resize(expected_layers);
				layer_presized = true;
			}
		} else if (tag_sv == "selected") {
			level_state_data[SN_SELECTED_LAYER_IDX] = reader.next_int();
		} else if (tag_sv == "cp") {
			camera_pos = reader.next_vector3();
		} else if (tag_sv == "cbr") {
			camera_base_rotation = reader.next_vector3();
		} else if (tag_sv == "crr") {
			camera_rot_rotation = reader.next_vector3();
		} else if (tag_sv == "e") {
			Dictionary entity;
			entity[SN_NAME] = reader.next_token();
			int type = reader.next_int();
			entity[SN_TYPE] = type;
			entity[SN_POSITION] = reader.next_vector3i();
			
			if (entities_version >= 3){
				//entities have a layer
				entity[SN_LAYER] = reader.next_int();
			} else {
				entity[SN_LAYER] = 0;
			}
			
			int flags = reader.next_int();
			if (flags & 0x01) entity[SN_DIR] = reader.next_int() - 1;
			if (flags & 0x02) entity[SN_META] = reader.next_token();
			if (flags & 0x04) entity[SN_ASSET_NAME] = reader.next_token();
			if (flags & 0x08) {
				entity[SN_COLOUR] = (int32_t)reader.next_u8();
			}
			if (entities_version >= 6) {
				// Compatibility for malformed v6 text files written before attribution fields
				// were emitted. Type 3 still has two Vector3i size fields after attribution.
				const int required_trailing_tokens = (type == 3) ? 6 : 0;
				if (reader.remaining_token_count() >= 4 + required_trailing_tokens) {
					entity[SN_PLACED_USER_ID] = reader.next_token();
					entity[SN_PLACED_USER_DISPLAY_NAME] = reader.next_token();
					entity[SN_EDITED_USER_ID] = reader.next_token();
					entity[SN_EDITED_USER_DISPLAY_NAME] = reader.next_token();
				} else {
					entity[SN_PLACED_USER_ID] = String();
					entity[SN_PLACED_USER_DISPLAY_NAME] = String();
					entity[SN_EDITED_USER_ID] = String();
					entity[SN_EDITED_USER_DISPLAY_NAME] = String();
				}
			}
			
			if (type == 3) {
				entity[SN_SIZE_EDS] = reader.next_vector3i();
				entity[SN_SIZE_WUN] = reader.next_vector3i();
			}
			if (entity_presized && entity_write_idx < entities.size()) {
				entities.set(entity_write_idx, entity);
				entity_write_idx++;
			} else {
				entities.append(entity);
			}
		}
	}

	if (voxel_presized && voxel_write_idx < voxel_data.size()) {
		voxel_data.resize(voxel_write_idx);
	}
	if (layer_presized && layer_write_idx < layers.size()) {
		layers.resize(layer_write_idx);
	}
	if (entity_presized && entity_write_idx < entities.size()) {
		entities.resize(entity_write_idx);
	}

	level_state_data[SN_VOXEL_DATA] = voxel_data;
	level_state_data[SN_LAYERS] = layers;
	
	Dictionary entities_dict;
	entities_dict[SN_VERSION] = entities_version;
	entities_dict[SN_ENTITIES] = entities;
	
	savedat.append(level_state_data);
	savedat.append(camera_pos);
	savedat.append(camera_base_rotation);
	savedat.append(camera_rot_rotation);
	savedat.append(entities_dict);

	return savedat;
}

Ref<Mesh> OeufSerializer::create_cube_mesh() const {
	Ref<ArrayMesh> box_mesh = memnew(ArrayMesh);
	
	// Create vertices for a unit cube (centered at origin, size 1x1x1)
	// 8 vertices of a cube
	PackedVector3Array vertices;
	vertices.push_back(Vector3(-0.5, -0.5, -0.5)); // 0
	vertices.push_back(Vector3(0.5, -0.5, -0.5));  // 1
	vertices.push_back(Vector3(0.5, 0.5, -0.5));   // 2
	vertices.push_back(Vector3(-0.5, 0.5, -0.5));  // 3
	vertices.push_back(Vector3(-0.5, -0.5, 0.5));  // 4
	vertices.push_back(Vector3(0.5, -0.5, 0.5));   // 5
	vertices.push_back(Vector3(0.5, 0.5, 0.5));    // 6
	vertices.push_back(Vector3(-0.5, 0.5, 0.5));   // 7
	
	// Create indices for 12 triangles (2 per face, 6 faces)
	PackedInt32Array indices;
	// Front face (z = 0.5)
	indices.push_back(4); indices.push_back(5); indices.push_back(6);
	indices.push_back(4); indices.push_back(6); indices.push_back(7);
	// Back face (z = -0.5)
	indices.push_back(1); indices.push_back(0); indices.push_back(3);
	indices.push_back(1); indices.push_back(3); indices.push_back(2);
	// Top face (y = 0.5)
	indices.push_back(7); indices.push_back(6); indices.push_back(2);
	indices.push_back(7); indices.push_back(2); indices.push_back(3);
	// Bottom face (y = -0.5)
	indices.push_back(0); indices.push_back(1); indices.push_back(5);
	indices.push_back(0); indices.push_back(5); indices.push_back(4);
	// Right face (x = 0.5)
	indices.push_back(5); indices.push_back(1); indices.push_back(2);
	indices.push_back(5); indices.push_back(2); indices.push_back(6);
	// Left face (x = -0.5)
	indices.push_back(0); indices.push_back(4); indices.push_back(7);
	indices.push_back(0); indices.push_back(7); indices.push_back(3);
	
	// Create the arrays structure for add_surface_from_arrays
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = vertices;
	arrays[Mesh::ARRAY_INDEX] = indices;
	
	box_mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES, arrays);
	
	return box_mesh;
}
