#ifndef VOXEL_MESHER_H
#define VOXEL_MESHER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <vector>
#include <map>
#include <unordered_map>
#include <cstdint>

namespace godot {

class VoxelMesher : public RefCounted {
	GDCLASS(VoxelMesher, RefCounted)

private:
	struct FaceData {
		std::vector<int> indices;
		int uv_pattern_index;
		int tile_voffset;
		bool occupy_face;
		int face_occupancy; // Enum value
	};

	struct ShapeVariant {
		std::vector<Vector3> vertices;
		std::vector<FaceData> faces; // 6 faces
		// Pre-calculated wobbled vertices could be cached per voxel, not per shape
	};

	// Flattened array: key = shape_type | (rotation << 4) | (vflip << 6)
	// Encodes all combinations in a single byte: shape_type (0-12, 4 bits), rotation (0-3, 2 bits), vflip (0-1, 1 bit)
	// 256 possible combinations - direct array access with zero hash overhead!
	ShapeVariant shape_database[256];
	bool shape_lookup_valid[256]; // Track which entries are valid
	
	// Direct array lookup: points to shape_database entries
	const ShapeVariant* shape_lookup_array[256];
	
	// Pre-computed face occupancies: flattened array [key * 6 + face_dir] = occupancy value
	// Eliminates repeated shape->faces[dir]->face_occupancy indirection in neighbor checks
	// 256 shape variants × 6 faces = 1536 bytes - flattened for better cache locality
	int8_t face_occupancy_cache[256 * 6];

	// Pre-computed occupancy_fits lookup table: flattened array [subject * 8 + container] -> bool
	// Occupancy values: EMPTY=-1, TRI0-3=0-3, QUAD=4, OCTAGON=5, SLIM=6
	// Maps to indices by adding 1: EMPTY->0, 0->1, 1->2, ..., 6->7
	// 8×8 = 64 bytes - flattened for better cache locality
	bool occupancy_fits_table[8 * 8];

	// uv_patterns[index] -> vector of Vector2
	std::vector<std::vector<Vector2>> uv_patterns;
	
	Ref<FastNoiseLite> noise1;
	Ref<FastNoiseLite> noise2;
	Ref<FastNoiseLite> noise3;
	
	// Cached noise pointers - set once, reused across all chunks (195 calls!)
	// Eliminates repeated .ptr() calls in hot path
	FastNoiseLite *cached_noise1;
	FastNoiseLite *cached_noise2;
	FastNoiseLite *cached_noise3;
	
	// Reusable buffers - pre-allocated and cleared between calls to avoid allocations
	// Since size_x/y/z are constant, we can reuse these across all 190 calls
	std::vector<Vector3> final_vertices;
	std::vector<Vector3> final_normals;
	std::vector<Color> final_normals_smoothed;
	std::vector<Vector2> final_uvs;
	
	struct VoxelData {
		int16_t shape_type;
		int16_t tx, ty;
		int8_t rot;
		bool vflip;
		int8_t layer;
	} __attribute__((packed));
	
	struct CachedVoxelInfo {
		const ShapeVariant *shape_ptr;
		uint8_t lookup_key;
		Vector3i voxel_pos;
		int local_x, local_y, local_z;
		bool valid;
	};
	
	std::vector<VoxelData> unpacked_props;
	std::vector<Vector3i> unpacked_voxels;
	std::vector<bool> layers_vis;
	std::vector<int> grid_cache;
	std::vector<CachedVoxelInfo> voxel_cache;
	std::vector<Vector3> cached_wobbled_local_verts;
	std::vector<Color> cached_vertex_colors;
	
	// Track current chunk dimensions to resize grid_cache only when needed
	int cached_size_x, cached_size_y, cached_size_z;
	
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

	Ref<ArrayMesh> generate_simplified_mesh(
		const Vector3i &chunk_coord,
		const Array &voxels,
		int size_x, int size_y, int size_z
	);
};

} // namespace godot

#endif // VOXEL_MESHER_H

