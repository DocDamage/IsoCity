extends RefCounted

const Document=preload("res://scripts/builder/document.gd")
const Store=preload("res://scripts/builder/project_store.gd")
const Assets=preload("res://scripts/builder/cooperative_plan.gd")
const MAX_BYTES: int=32*1024*1024
const FORMAT: String="IsoCity creation"

static func failure(message: String) -> Dictionary: return {"ok":false,"reason":message}
static func parse_json(raw: String) -> Variant:
	var parser:=JSON.new(); return parser.data if parser.parse(raw)==OK else null
static func text_valid(value: Variant,limit: int,required: bool=false) -> bool:
	return value is String and value.length()<=limit and (not required or not value.strip_edges().is_empty())
static func metadata_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=6: return false
	for spec in [["title",100,true],["author",100,true],["description",2000,false],["license",500,true],["source_url",500,false],["kind",10,true]]:
		if not text_valid(value.get(spec[0]),spec[1],spec[2]): return false
	return value["kind"] in ["city","assembly"]
static func credits_valid(value: Variant) -> bool:
	return value is Array and value.size()<=64 and value.all(func(entry: Variant):return metadata_valid(entry))
static func credits(source: Dictionary) -> Array:
	return source.get("document",{}).get("creation_credits",[]) if source["kind"]=="city" else source["assembly"].get("creation_credits",[])
static func imported_credits(creation: Dictionary) -> Array:
	var result: Array=creation.get("credits",[]).duplicate(true)
	if not result.has(creation["metadata"]): result.append(creation["metadata"].duplicate(true))
	return result
static func source_document(source: Dictionary) -> Dictionary:
	if source.get("kind")=="city": return source.get("document",{})
	var assembly: Dictionary=source.get("assembly",{})
	return {"mode":assembly.get("mode",""),"title":assembly.get("name","Assembly"),"objects":assembly.get("objects",[]),"tiles":[],"night":false}
static func source_valid(source: Variant) -> bool:
	if not source is Dictionary: return false
	if source.get("kind")=="city": return source.get("document") is Dictionary and source["document"].get("mode") is String and source["document"]["mode"] in ["2d","3d"]
	if source.get("kind")=="assembly": return source.get("assembly") is Dictionary and source["assembly"].get("objects") is Array and source["assembly"].get("mode") in ["2d","3d"] and source["assembly"].get("name") is String
	return false
static func required_assets(data: Dictionary,library: RefCounted) -> Array:
	var result: Array=[]; var ids: Array=Assets.required_assets(data,library).keys(); ids.sort()
	for id in ids:
		var asset: Dictionary=library.assets.get(id,{}); var info: Dictionary=asset.get("data",{})
		result.append({"id":id,"name":asset.get("name",id),"pack":library.pack_name(asset),"author":str(info.get("author","")),"license":str(info.get("license","See supplied pack notices")),"source_url":str(info.get("source_url",""))})
	return result
static func attribution(requirements: Array,library: RefCounted) -> String:
	var result: String="Asset requirements and attribution\n\nThese downloads contain layout data and a preview. Install the listed asset packs in IsoCity before importing. Asset rights remain with their respective creators. The creation's license does not replace asset licenses.\n\n"
	var notices: Dictionary={}
	for entry in requirements:
		result+="%s [%s]\nPack: %s\nAuthor: %s\nLicense: %s\nSource: %s\n\n" % [entry["name"],entry["id"],entry["pack"],entry["author"],entry["license"],entry["source_url"]]
		var folder: String=library.assets[entry["id"]]["path"].get_base_dir()
		# Sprite prefabs live outside the asset pack; follow their source metadata too.
		var folders: Array=[folder]
		var references:=RegEx.new(); references.compile('path="(res://assets/[^"\\n]+)"')
		for reference in references.search_all(FileAccess.get_file_as_string(library.assets[entry["id"]]["path"])): folders.append(reference.get_string(1).get_base_dir())
		for path in library.assets[entry["id"]].get("data",{}).get("source_files",[]):
			if path is String and path.begins_with("res://assets/"): folders.append(path.get_base_dir())
		if entry["id"].begins_with("2d:") and not entry["id"].contains(":Custom/"): folders.append("res://assets/pixel_isometric")
		for start in folders:
			folder=start
			while folder.begins_with("res://assets/"):
				for file in DirAccess.get_files_at(folder):
					if file.get_basename().to_lower() in ["license","licence","credits","attribution"]:
						var path: String=folder.path_join(file)
						if not notices.has(path): notices[path]=FileAccess.get_file_as_string(path).left(262144)
				folder=folder.get_base_dir()
	for path in notices: result+="--- "+path.trim_prefix("res://")+" ---\n"+notices[path]+"\n\n"
	return result
static func prepare(source: Dictionary,metadata: Dictionary,preview: Image,library: RefCounted) -> Dictionary:
	if not metadata_valid(metadata) or not source_valid(source) or source.get("kind")!=metadata["kind"]: return failure("Enter a title, author and creation license.")
	var data: Dictionary=source_document(source)
	if not Document.valid(data,data.get("mode",""),library): return failure("The creation contains invalid records or unavailable assets.")
	if not credits_valid(credits(source)) or credits(source).size()>=64: return failure("The creation attribution history is invalid or exceeds 63 prior creators.")
	if source["kind"]=="assembly" and data["objects"].is_empty(): return failure("Choose a nonempty assembly.")
	if preview==null or preview.is_empty(): return failure("Generate a preview before publishing.")
	var image: Image=preview.duplicate(); image.resize(800,500,Image.INTERPOLATE_LANCZOS)
	var raw: String=JSON.stringify(source); var requirements: Array=required_assets(data,library)
	var value: Dictionary={"format":FORMAT,"version":1,"metadata":metadata.duplicate(true),"source":raw,"source_sha256":raw.sha256_text(),"requirements":requirements,"attribution":attribution(requirements,library),"preview_png":Marshalls.raw_to_base64(image.save_png_to_buffer())}
	value["credits"]=credits(source).duplicate(true)
	for credit in value["credits"]: value["attribution"]+="Prior creation: %s\nCreator: %s\nCreation license: %s\nSource: %s\n\n" % [credit["title"],credit["author"],credit["license"],credit["source_url"]]
	value["id"]=(raw+JSON.stringify(metadata)).sha256_text().substr(0,32)
	if JSON.stringify(value).to_utf8_buffer().size()>MAX_BYTES: return failure("This creation exceeds the 32 MiB sharing limit.")
	return {"ok":true,"creation":value}
static func inspect(value: Variant,library: RefCounted) -> Dictionary:
	if not value is Dictionary or value.get("format")!=FORMAT or value.get("version")!=1 or not Store.valid_id(value.get("id")): return failure("This is not a supported IsoCity creation.")
	if not metadata_valid(value.get("metadata")) or not text_valid(value.get("source"),MAX_BYTES) or not text_valid(value.get("attribution"),8*1024*1024): return failure("The creation metadata is damaged.")
	if value.get("source_sha256")!=value["source"].sha256_text(): return failure("The creation source checksum does not match.")
	var source: Variant=parse_json(value["source"])
	if not source_valid(source) or source.get("kind")!=value["metadata"]["kind"]: return failure("The creation source is invalid.")
	if source["kind"]=="assembly" and source["assembly"]["objects"].is_empty(): return failure("The shared assembly is empty.")
	if not credits_valid(value.get("credits",[])) or not credits_valid(credits(source)) or value.get("credits",[])!=credits(source) or value.get("credits",[]).size()>=64: return failure("The creation attribution history is damaged.")
	var mode: String=source_document(source).get("mode","")
	if not mode in ["2d","3d"]: return failure("The creation view is invalid.")
	if not value.get("requirements") is Array or value["requirements"].size()>10000: return failure("The asset requirements are invalid.")
	var missing: Array=[]; var seen: Dictionary={}
	for entry in value["requirements"]:
		if not entry is Dictionary or not text_valid(entry.get("id"),512,true) or seen.has(entry["id"]): return failure("The asset requirements are damaged.")
		for key in ["name","pack","author","license","source_url"]:
			if not text_valid(entry.get(key),2048): return failure("The asset information is damaged.")
		seen[entry["id"]]=true
		if not library.assets.has(entry["id"]) or library.assets[entry["id"]].get("unavailable",false): missing.append(entry["id"])
	# Validate with the actual catalog only after requirements are installed.
	var data: Dictionary=source_document(source)
	if missing.is_empty():
		if not Document.valid(data,mode,library): return failure("The source contains invalid records.")
		if Assets.required_assets(data,library).keys().any(func(id: String):return not seen.has(id)): return failure("The source omits required asset information.")
	if not text_valid(value.get("preview_png"),6*1024*1024,true): return failure("The preview is invalid.")
	var base64:=RegEx.new(); base64.compile("^[A-Za-z0-9+/]+={0,2}$")
	if value["preview_png"].length()%4!=0 or base64.search(value["preview_png"])==null: return failure("The preview encoding is invalid.")
	var png: PackedByteArray=Marshalls.base64_to_raw(value["preview_png"])
	# Check fixed dimensions before asking the image decoder to allocate pixels.
	if png.size()<24 or png.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]) or png.slice(16,24)!=PackedByteArray([0,0,3,32,0,0,1,244]): return failure("The preview must be an 800×500 PNG.")
	var image:=Image.new()
	if image.load_png_from_buffer(png)!=OK: return failure("The preview could not be read.")
	return {"ok":true,"creation":value,"source":source,"preview":image,"missing":missing,"mode":mode}
static func read(path: String,library: RefCounted) -> Dictionary:
	var file:=FileAccess.open(path,FileAccess.READ)
	if not file: return failure("The creation file could not be opened.")
	if file.get_length()>MAX_BYTES: file.close(); return failure("The creation exceeds the 32 MiB sharing limit.")
	var raw: String=file.get_as_text(); file.close(); return inspect(parse_json(raw),library)
static func escape(value: String) -> String:
	return value.replace("&","&amp;").replace("<","&lt;").replace(">","&gt;").replace('"',"&quot;").replace("'","&#39;")
static func gallery_page(entries: Array) -> String:
	var html: String='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>IsoCity creations</title><link rel="icon" href="data:,"><style>body{margin:0;background:#101c26;color:#eff7fa;font:17px system-ui}main{max-width:1100px;margin:auto;padding:32px}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}article{background:#1b2d3b;border:1px solid #536b7c;border-radius:16px;overflow:hidden}img{width:100%;aspect-ratio:8/5;object-fit:cover}article div{padding:20px}a{color:#88edce}p{white-space:pre-wrap;overflow-wrap:anywhere}summary{cursor:pointer;padding:12px 0}</style><main><h1>IsoCity creations</h1><p>Download a city or assembly, then open Creation sharing in IsoCity to review and import it. Install its required asset packs first. These downloads contain layout data and previews.</p><section>'
	for entry in entries:
		var info: Dictionary=entry["metadata"]; var id: String=entry["id"]
		html+='<article><img src="previews/%s.png" alt="%s"><div><h2>%s</h2><p>%s · %s · %s</p><p>%s</p><p>Creation license: %s</p><a download href="creations/%s.isocity-share.json">Download %s</a><details><summary>Asset requirements and attribution</summary><p>%s</p></details></div></article>' % [id,escape(info["title"]),escape(info["title"]),escape(info["author"]),escape(info["kind"]),escape(entry["mode"]),escape(info["description"]),escape(info["license"]),id,escape(info["kind"]),escape(entry["attribution"])]
	return html+'</section><p>Made with IsoCity. Creator licenses apply to their layouts; asset licenses remain separate.</p></main></html>'
static func entries(folder: String) -> Array:
	var raw: Variant=Store.read_json(folder.path_join("gallery.json"),[]); var result: Array=[]
	if raw is Array:
		for entry in raw:
			if entry is Dictionary and Store.valid_id(entry.get("id")) and metadata_valid(entry.get("metadata")) and entry.get("mode") in ["2d","3d"] and text_valid(entry.get("attribution"),8*1024*1024): result.append(entry)
	return result
static func write_text(path: String,value: String) -> bool:
	if not Store.prepare_parent(path): return false
	var temporary: String=path+"."+Store.new_id()+".partial"; var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if not file: return false
	file.store_string(value); var result: Error=file.get_error(); file.close()
	if result==OK: result=DirAccess.rename_absolute(temporary,path)
	if result!=OK: DirAccess.remove_absolute(temporary)
	return result==OK
static func publish(value: Dictionary,folder: String,library: RefCounted) -> Dictionary:
	var checked: Dictionary=inspect(value,library)
	if not checked["ok"]: return checked
	if not checked["missing"].is_empty(): return failure("Install all required assets before publishing.")
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder): return failure("Choose an existing gallery folder.")
	var id: String=value["id"]; var path: String=folder.path_join("creations/"+id+".isocity-share.json")
	if not Store.write_json(path,value): return failure("The downloadable creation could not be saved.")
	var image_path: String=folder.path_join("previews/"+id+".png")
	if not Store.prepare_parent(image_path) or checked["preview"].save_png(image_path)!=OK: return failure("The gallery preview could not be saved.")
	var records: Array=entries(folder).filter(func(entry: Dictionary):return entry["id"]!=id)
	records.append({"id":id,"metadata":value["metadata"],"mode":checked["mode"],"attribution":value["attribution"]})
	if not Store.write_json(folder.path_join("gallery.json"),records) or not write_text(folder.path_join("index.html"),gallery_page(records)): return failure("The gallery index could not be saved. The creation download is retained.")
	write_text(folder.path_join("README.txt"),"IsoCity creation gallery\n\nOpen index.html to browse and download creations. Upload this entire folder to any static website host to publish it online, or distribute the folder directly. Keep creations/, previews/, gallery.json and index.html together. Import .isocity-share.json through Creation sharing in IsoCity. Required assets are listed on each card and reviewed before import. Layout downloads do not include executable scripts or third-party asset files. For a self-contained playable city use IsoCity's separate portable Godot project export.\n")
	return {"ok":true,"path":path,"index":folder.path_join("index.html"),"id":id}
