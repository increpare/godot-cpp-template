extends SceneTree

func _init() -> void:
	var serializer := OeufSerializer.new()
	var file_names := ["eggworld.txt", "mini_city.txt"]
	var iterations := 10
	var failures := 0

	for file_name in file_names:
		var path := ProjectSettings.globalize_path("res://../sample_files/%s" % file_name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("Failed to read %s" % path)
			failures += 1
			continue

		var t0 := Time.get_ticks_usec()
		var parsed := []
		var out := ""
		for i in iterations:
			parsed = serializer.deserialize_from_string(text)
			out = serializer.serialize_to_string(parsed)
		var t1 := Time.get_ticks_usec()

		var total_us := t1 - t0
		var avg_us := float(total_us) / float(iterations)
		var equal := out == text
		print("%s roundtrip_avg_us=%.1f iterations=%d equal=%s len=%d" % [
			file_name, avg_us, iterations, str(equal), out.length()
		])
		if not equal:
			failures += 1

	quit(failures)
