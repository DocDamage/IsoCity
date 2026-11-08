extends RefCounted

const Plan = preload("res://scripts/builder/ambience_plan.gd")

static func record(studio: Control, kind: String, path: String) -> Error:
	var doc: RefCounted = studio.interior_tools.root_document(studio.mode)
	var data: Dictionary = doc.data
	var original: Variant = data.get("ambience")
	var isolated: Dictionary = Plan.settings(data)
	for name in Plan.KINDS: isolated[name] = 1.0 if name == kind else 0.0
	data["ambience"] = isolated
	await studio.get_tree().create_timer(.5).timeout
	var bus: int = AudioServer.get_bus_index("IsoCity Ambience")
	var index: int = AudioServer.get_bus_effect_count(bus)
	var capture := AudioEffectRecord.new()
	capture.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus,capture)
	capture.set_recording_active(true)
	await studio.get_tree().create_timer(3.0).timeout
	capture.set_recording_active(false)
	var clip: AudioStreamWAV = capture.get_recording()
	AudioServer.remove_bus_effect(bus,index)
	if original == null: data.erase("ambience")
	else: data["ambience"] = original
	if not clip or clip.get_length() < 2.5: return ERR_INVALID_DATA
	return clip.save_to_wav(path)
