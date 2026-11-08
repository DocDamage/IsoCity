extends RefCounted
const Styles=preload("res://scripts/builder/asset_styles.gd")
var studio: Control
var choice: OptionButton
var simple_choice: OptionButton
var note: Label
var simple_note: Label
var clear_context: Button
var explicit_id: String=""
var include_all: bool=false
var settings_path: String="user://studio_style_order.json"
var reports: Dictionary={}
var context: Dictionary={}
var context_name: String=""
var suggested_count: int=0
var elapsed: float=0
var signature: int=0

func _init(host: Control,column: Node,after: Control) -> void:
	studio=host
	if studio.storage_enabled:restore()
	choice=make_choice(column);column.move_child(choice,after.get_index()+1)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",12);column.add_child(note);column.move_child(note,choice.get_index()+1)
	clear_context=Button.new();clear_context.text="Clear style context";column.add_child(clear_context);column.move_child(clear_context,note.get_index()+1);clear_context.pressed.connect(clear_anchor)

func make_choice(parent: Node) -> OptionButton:
	var result:=OptionButton.new();result.fit_to_longest_item=false;result.clip_text=true
	result.add_item("Suggested first");result.add_item("All styles");result.select(1 if include_all else 0)
	result.tooltip_text="Compatibility ordering only. All matching styles remain available; text relevance stays first. Suggestions use source metadata and do not guarantee a visual fit."
	parent.add_child(result);result.item_selected.connect(func(index: int):set_include_all(index==1));return result

func add_simple(parent: Node,words_parent: Node) -> void:
	simple_choice=make_choice(parent);simple_choice.custom_minimum_size.x=185
	simple_note=Label.new();simple_note.add_theme_font_size_override("font_size",12);simple_note.clip_text=true;simple_note.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;words_parent.add_child(simple_note)

func restore() -> void:
	var value: Variant=studio.Store.read_json(settings_path,{})
	include_all=value.get("include_all_styles",false) if value is Dictionary and value.get("include_all_styles") is bool else false

func set_include_all(value: bool) -> void:
	include_all=value;choice.select(1 if value else 0)
	if simple_choice:simple_choice.select(1 if value else 0)
	if studio.storage_enabled and not studio.Store.write_json(settings_path,{"include_all_styles":value}):studio.status.text="Style order applied for this session; preferences could not be saved."
	studio.page=0;studio.refresh_library()

func anchor(id: String) -> void:
	if not studio.library.assets.has(id):return
	explicit_id=id;set_include_all(false)
	studio.status.text="Suggested styles are ordered for "+studio.library.assets[id]["name"]+". Every search match remains available."

func clear_anchor() -> void:
	explicit_id="";studio.page=0;studio.refresh_library()

func resolve_context() -> void:
	context={};context_name=""
	var browser: RefCounted=studio.asset_browser
	var selected: Array=studio.selection_items()
	var id: String=explicit_id
	if id.is_empty() and browser and browser.theme_filter in studio.library.themes.KEYS:
		context={"id":"","themes":[browser.theme_filter]};context_name=studio.library.themes.label(browser.theme_filter)+" theme";return
	if id.is_empty():id=selected[0]["asset"] if selected.size()==1 else studio.asset_id
	if not studio.library.assets.has(id):return
	context=studio.library.styles.profile(id);context_name=studio.library.assets[id]["name"]
	if explicit_id.is_empty() and selected.size()==1 and selected[0]["asset"]==id:
		context["scale"]=selected[0].get("scale",context.get("default_scale",1))
		if not selected[0].get("colors",[]).is_empty():context["palette"]="";context_name+=" (source style; custom paint not compared)"
	elif explicit_id.is_empty() and studio.asset_id==id:context["scale"]=studio.scale_input.value

func order(found: Array[Dictionary],query: String) -> Array[Dictionary]:
	resolve_context();reports.clear();suggested_count=0
	var result: Array[Dictionary]=found.duplicate()
	if include_all or context.is_empty():return result
	var positions: Dictionary={};var text_ranks: Dictionary={};var terms: PackedStringArray=studio.library.search_index.words(query)
	for index in result.size():
		var asset: Dictionary=result[index];var id: String=asset["id"]
		positions[id]=index;text_ranks[id]=studio.library.search_index.rank(asset,terms) if not terms.is_empty() else 0
		reports[id]=Styles.compare(studio.library.styles.profile(id),context,studio.mode)
		if reports[id]["suggested"]:suggested_count+=1
	result.sort_custom(func(a: Dictionary,b: Dictionary):
		if text_ranks[a["id"]]!=text_ranks[b["id"]]:return text_ranks[a["id"]]>text_ranks[b["id"]]
		if reports[a["id"]]["score"]!=reports[b["id"]]["score"]:return reports[a["id"]]["score"]>reports[b["id"]]["score"]
		return positions[a["id"]]<positions[b["id"]])
	return result

func explanation(id: String) -> String:
	var report: Dictionary=reports.get(id,{})
	if report.is_empty():return "All styles remain available. Style metadata can be partial; compare placement size and supplied artwork."
	return ("Suggested for "+context_name+". " if report["suggested"] else "Other matching style. ")+" ".join(report["reasons"])+" "+" ".join(report["cautions"])+" Suggestions are source-based hints, not an assurance of exact fit."

func refresh() -> void:
	choice.select(1 if include_all else 0)
	if simple_choice:simple_choice.select(1 if include_all else 0)
	var text: String="All styles · original search order." if include_all else "Choose a theme, select an asset, or use Suggest this style in asset details."
	if not include_all and not context.is_empty():text="Suggested for "+context_name+" · %d matches in these results. All styles remain."%suggested_count
	if not include_all and not context.is_empty() and suggested_count<3:text+=" Limited matching metadata or a sparse collection; inspect other styles too."
	note.text=text;note.tooltip_text=text;clear_context.visible=not explicit_id.is_empty()
	if simple_note:simple_note.text=text;simple_note.tooltip_text=text
	for card in studio.cards.get_children():
		var id: String=card.asset_id;var report: Dictionary=reports.get(id,{})
		card.tooltip_text+="\n"+explanation(id)
		if report.get("suggested",false) and is_instance_valid(card.inspect_button):
			card.inspect_button.text="Suggested";card.inspect_button.add_theme_font_size_override("font_size",10)
			card.inspect_button.tooltip_text="Inspect suggested artwork. "+explanation(id)
			card.reflow(studio.thumbnail_size,studio.accessibility_settings.text_scale)
	signature=context_signature()

func context_signature() -> int:
	resolve_context();return hash([explicit_id,context,include_all,studio.mode,studio.library.styles.revision])

func tick(delta: float) -> void:
	elapsed+=delta
	if elapsed<.4:return
	elapsed=0
	if not include_all and context_signature()!=signature:studio.call_deferred("refresh_library")
