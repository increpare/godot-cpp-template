extends SceneTree

func _init() -> void:
	var serializer := OeufSerializer.new()
	var file_names := ["eggworld.txt", "mini_city.txt"]
	var failures := 0
	var iterations := 30

	for file_name in file_names:
		var path := ProjectSettings.globalize_path("res://../sample_files/%s" % file_name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("Failed to read %s" % path)
			failures += 1
			continue

		var parsed := serializer.deserialize_from_string(text)
		var warm := serializer.serialize_to_string(parsed)
		if warm.length() != text.length():
			failures += 1

		var t0 := Time.get_ticks_usec()
		var last := ""
		for i in iterations:
			last = serializer.serialize_to_string(parsed)
		var t1 := Time.get_ticks_usec()

		var total_us := t1 - t0
		var avg_us := float(total_us) / float(iterations)
		var equal := last == text

		print("%s serialize_avg_us=%.1f iterations=%d equal=%s out_len=%d" % [
			file_name, avg_us, iterations, str(equal), last.length()
		])

		if not equal:
			failures += 1

	quit(failures)
