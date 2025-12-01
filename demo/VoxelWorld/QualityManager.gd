extends Node

var environment:Environment = preload("res://VoxelWorld/Environments/overworld.tres")
var rain_particles_processmaterial:ParticleProcessMaterial = preload("res://VoxelWorld/Materials/rain_particle_material.tres")

var terrain_material:ShaderMaterial = preload("res://VoxelWorld/Materials/tilemap.tres")
var outline_material:ShaderMaterial = preload("res://VoxelWorld/Materials/tilemap_outline.tres")

var title_background_material:ShaderMaterial = preload("res://Menus/Materials/TitleBackground.tres")
var blur_shader:Shader = preload("res://Menus/Shaders/blur.gdshader")

var title_raindrops:ShaderMaterial = preload("res://Menus/Materials/TitleRaindrops.tres")
var title_raindrops_shader:Shader = preload("res://Menus/Shaders/teardrop.gdshader")
var title_raindrops_cheap:Shader = preload("res://Menus/Shaders/teardrop_cheap.gdshader")

var camera_attributes:CameraAttributes = preload("res://player/Misc/cameraattributes.tres")

func set_quality(quality:int):
	#print("setting quality to ", quality)
	match quality:
		0:#fast mode
			environment.glow_enabled = false
			environment.ssil_enabled = false
			var col_value = rain_particles_processmaterial.get("collision_mode")
			print(col_value)
			rain_particles_processmaterial.set("collision_mode",ParticleProcessMaterial.COLLISION_DISABLED)

			var shadowcasters = get_tree().get_nodes_in_group("shadowcaster")
			for shadowcaster:DirectionalLight3D in shadowcasters:
					shadowcaster.shadow_enabled = false
			
			terrain_material.next_pass = null
			terrain_material.set("shader_parameter/fog_depth_end_multiplier", 1.7142)

			title_background_material.shader = null

			title_raindrops.shader = title_raindrops_cheap
			
			get_viewport().use_debanding = false
			RenderingServer.screen_space_roughness_limiter_set_active(false,0.25,0.18)

			camera_attributes.exposure_multiplier=1.1
			

		1:#good mode
			environment.glow_enabled = true
			environment.ssil_enabled = true    
			var col_value = rain_particles_processmaterial.get("collision_mode")
			print(col_value)
			rain_particles_processmaterial.set("collision_mode",ParticleProcessMaterial.COLLISION_RIGID)
			
			var shadowcasters = get_tree().get_nodes_in_group("shadowcaster")
			for shadowcaster:DirectionalLight3D in shadowcasters:
				shadowcaster.shadow_enabled = true

			terrain_material.next_pass = outline_material
			terrain_material.set("shader_parameter/fog_depth_end_multiplier", 1.0)

			title_background_material.shader = blur_shader

			title_raindrops.shader = title_raindrops_shader

			get_viewport().use_debanding = true
			RenderingServer.screen_space_roughness_limiter_set_active(true,0.25,0.18)
			camera_attributes.exposure_multiplier=1.0
