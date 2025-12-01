#ifndef VOXEL_MESHER_H
#define VOXEL_MESHER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <vector>
#include <map>

namespace godot {

class VoxelMesher : public RefCounted {
	GDCLASS(VoxelMesher, RefCounted)

private:
	struct FaceData {
		std::vector<int> indices;
		String uv_name;
		int tile_voffset;
		bool occupy_face;
		int face_occupancy; // Enum value
	};

	struct ShapeVariant {
		std::vector<Vector3> vertices;
		std::vector<FaceData> faces; // 6 faces
		// Pre-calculated wobbled vertices could be cached per voxel, not per shape
	};

	// database[shape_index][rotation][vflip]
	std::vector<std::vector<std::vector<ShapeVariant>>> shape_database;

	// uv_patterns[name] -> vector of Vector2
	std::map<String, std::vector<Vector2>> uv_patterns;

	Ref<FastNoiseLite> noise1;
	Ref<FastNoiseLite> noise2;
	Ref<FastNoiseLite> noise3;
	
	// Constants
	const float TILE_W = 16.0f;
	const float TILE_H = 16.0f;
	float tex_width = 1.0f;
	float tex_height = 1.0f;
	float tile_w_local = 1.0f;
	float tile_h_local = 1.0f;
	Vector2 du;
	Vector2 dv;
	const int FACE_UV_COLGROUP_SIZE = 3;

	// Internal helpers
	void _cache_wobbled_verts(const Vector3i &voxel, const ShapeVariant &shape, 
		const Vector3i &offset, std::vector<Vector3> &out_verts, std::vector<Color> &out_colors);

protected:
	static void _bind_methods();

public:
	VoxelMesher();
	~VoxelMesher();

	void initialize_noise(int seed);
	void set_texture_dimensions(float width, float height);
	void parse_shapes(const Array &gd_database, const Dictionary &gd_uv_patterns);

	// Returns a Dictionary containing arrays for ArrayMesh (vertices, normals, uvs, etc.)
	Dictionary generate_chunk_mesh(
		const Vector3i &chunk_coord,
		const Array &voxels,
		const Array &voxel_properties,
		const Array &layer_visibility,
		int size_x, int size_y, int size_z
	);
};

} // namespace godot

#endif // VOXEL_MESHER_H

