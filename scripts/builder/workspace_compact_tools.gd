extends RefCounted

# Keep every workspace tool reachable without letting stacked tool rows consume
# the compact window's canvas. Save state remains outside this scrolling group.
var studio_ref: WeakRef
var center_ref: WeakRef
var scroll: ScrollContainer
var content: VBoxContainer
var records: Array=[]
var active: bool=false
func _init(studio: Control,center: Control) -> void:studio_ref=weakref(studio);center_ref=weakref(center)
func refresh() -> void:
	var studio: Control=studio_ref.get_ref();var center: Control=center_ref.get_ref()
	if not is_instance_valid(studio) or not is_instance_valid(center) or not studio.enhancements_ready:return
	var compact: bool=studio.get_viewport_rect().size.y<760 and not studio.workspace_layout.focus_mode and not (studio.consumer_shell and studio.consumer_shell.active)
	if compact==active:return
	active=compact
	if compact:
		if not is_instance_valid(scroll):
			scroll=ScrollContainer.new();scroll.name="CompactWorkspaceTools";scroll.follow_focus=true;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.custom_minimum_size.y=112
			content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content);center.add_child(scroll)
		records.clear()
		for child in center.get_children():
			if child==studio.canvas:break
			if child==scroll or child==studio.save_badge:continue
			records.append({"node":weakref(child),"index":child.get_index()})
		for entry in records:
			var child: Control=entry["node"].get_ref()
			if is_instance_valid(child) and child.get_parent()==center:child.reparent(content)
		center.move_child(scroll,0);scroll.show()
	else:
		for entry in records:
			var child: Control=entry["node"].get_ref()
			if is_instance_valid(child) and child.get_parent()==content:child.reparent(center);center.move_child(child,mini(entry["index"],center.get_child_count()-1))
		records.clear()
		if is_instance_valid(scroll):scroll.hide()
