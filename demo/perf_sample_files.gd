extends SceneTree

func _init() -> void:
	var serializer := OeufSerializer.new()
	var file_names := ["eggworld.txt", "mini_city.txt"]
	var failures := 0

	for file_name in file_names:
		var path := ProjectSettings.globalize_path("res://../sample_files/%s" % file_name)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			push_error("Failed to read %s" % path)
			failures += 1
			continue

		var t0 := Time.get_ticks_msec()
		var parsed := serializer.deserialize_from_string(text)
		var t1 := Time.get_ticks_msec()
		var reserialized := serializer.serialize_to_string(parsed)
		var t2 := Time.get_ticks_msec()

		var parse_ms := t1 - t0
		var serialize_ms := t2 - t1
		var equal := reserialized == text

		print("%s parse_ms=%d serialize_ms=%d input_len=%d output_len=%d equal=%s" % [
			file_name, parse_ms, serialize_ms, text.length(), reserialized.length(), str(equal)
		])

		if not equal:
			failures += 1

	quit(failures)
