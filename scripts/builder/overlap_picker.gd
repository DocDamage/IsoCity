extends RefCounted

var studio: Control
var popup: PopupMenu
var last_point := Vector2.ZERO
var last_document: int = 0

func _init(host: Control) -> void:
	studio=host
	studio.tools["select"].tooltip_text="Select and drag to move. Alt+click cycles stacked objects; Alt+Shift+click cycles back. Alt+right-click lists objects beneath the pointer. Page Down / Page Up also cycle."
	popup=PopupMenu.new()
	popup.name="ObjectsUnderPointer"
	studio.add_child(popup)
	popup.id_pressed.connect(func(id: int):
		var value: Variant=popup.get_item_metadata(popup.get_item_index(id))
		if value is Dictionary:studio._command(value["action"],null)
		else:choose(str(value))
	)

func available() -> bool:
	return not studio.walking and studio.tool=="select"

func candidates(at: Vector2) -> Array[String]:
	last_point=at
	last_document=studio.current().get_instance_id()
	return studio.worlds[studio.mode].pick_all(at)

func pointer() -> Vector2:
	var point: Vector2=studio.canvas.get_local_mouse_position()
	if Rect2(Vector2.ZERO,studio.canvas.size).has_point(point): return point
	return last_point if last_document==studio.current().get_instance_id() else studio.canvas.size*0.5

func choose(uid: String) -> void:
	popup.hide()
	var item: Dictionary=studio.current().object(uid)
	if item.is_empty() or not studio.Layers.editable(studio.current().data,item,studio.library):
		studio.refresh_controls()
		studio.status.text="That object is no longer available for editing."
		return
	studio.clear_placement()
	studio.selected_uid=uid
	studio.selected_uids.assign([uid])
	studio.marquee_active=false
	studio.stroke=false
	studio.drag_origins.clear()
	studio.refresh_controls()
	studio.status.text="Selected "+item.get("name",studio.library.assets[item["asset"]]["name"])+" · Alt+click cycles overlaps; Alt+right-click lists them."

func cycle(at: Vector2, step: int = 1) -> void:
	if studio.walking: return
	studio.finish_edit(at)
	var ids: Array[String]=candidates(at)
	if ids.is_empty(): studio.status.text="No editable objects under this pointer."; return
	var index: int=ids.find(studio.selected_uid)
	if index<0: index=-1 if step>0 else 0
	index=posmod(index+step,ids.size())
	choose(ids[index])
	studio.status.text+=" · %d of %d" % [index+1,ids.size()]

func show(at: Vector2) -> void:
	if studio.walking: return
	studio.finish_edit(at)
	popup.clear()
	var ids: Array[String]=candidates(at)
	for uid in ids:
		var item: Dictionary=studio.current().object(uid)
		var name: String=item.get("name",studio.library.assets[item["asset"]]["name"])
		var layer: String=studio.Layers.layer(item,studio.library)
		var group: String=item.get("group","")
		var text: String=name.left(44)+" · "+layer
		if not group.is_empty(): text+=" · "+str(studio.current().data.get("group_names",{}).get(group,group)).left(20)
		popup.add_item(text)
		var index: int=popup.item_count-1
		popup.set_item_metadata(index,uid)
		popup.set_item_tooltip(index,name+"\n"+item["asset"]+"\n"+layer)
	if ids.is_empty(): popup.add_item("No editable objects here"); popup.set_item_disabled(0,true)
	popup.add_separator()
	for spec in [["Frame selection","small_props_focus"],["Magnify selected props","small_props_magnify"],["Isolate selection","small_props_isolate"]]:
		popup.add_item(spec[0]);popup.set_item_metadata(popup.item_count-1,{"action":spec[1]});popup.set_item_disabled(popup.item_count-1,studio.selection_items().is_empty())
	var window: Vector2i=studio.get_window().size
	popup.max_size=Vector2i(mini(560,window.x-24),mini(340,window.y-48))
	var point: Vector2i=Vector2i(studio.canvas.get_global_rect().position+at+Vector2(10,10))
	popup.popup(Rect2i(point,Vector2i.ZERO))
	popup.position=Vector2i(clampi(point.x,0,maxi(0,window.x-popup.size.x)),clampi(point.y,24,maxi(24,window.y-popup.size.y-8)))
