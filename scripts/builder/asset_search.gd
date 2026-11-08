extends RefCounted

const SYNONYMS: Array = [
	["car", "automobile", "vehicle", "auto"], ["cafe", "coffee", "café"],
	["house", "home", "residence", "residential"], ["shop", "store", "retail"],
	["road", "street", "roadway"], ["pavement", "sidewalk", "footpath"],
	["sofa", "couch", "settee"], ["trash", "garbage", "rubbish", "waste"],
	["tree", "trees"], ["bicycle", "bike"], ["railway", "railroad"],
	["apartment", "flat"], ["lamp", "light", "lighting"]
]
var index: Dictionary = {}
var scores: Dictionary = {}
var postings: Dictionary = {}
var stems: Dictionary = {}
var queries: Dictionary = {}
var semantics: Dictionary = {}
var groups: Dictionary = {}
const SEMANTICS="res://resources/catalog/asset_semantics.json"
const ACCENTS=["àáâãäåāăą","çćĉċč","ďđ","èéêëēĕėęě","ĝğġģ","ĥħ","ìíîïĩīĭįı","ĵ","ķ","ĺļľŀł","ñńņň","òóôõöøōŏő","ŕŗř","śŝşš","ţťŧ","ùúûüũūŭůűų","ŵ","ýÿŷ","źżž"]
const LATIN="acdeghijklnorstuwyz"
const IRREGULAR_PLURALS={"people":"person","children":"child","shelves":"shelf","knives":"knife","leaves":"leaf","buses":"bus"}
const ES_ENDINGS=["ches","shes","xes","zes","sses"]

func clear() -> void:
	index.clear();scores.clear();postings.clear();stems.clear();queries.clear()

static func strings(value: Variant) -> Array[String]:
	var result: Array[String]=[]
	if value is Array:
		for item in value.slice(0,64):
			if item is String and item.length()<=240 and not item.is_empty() and item not in result:result.append(item)
	return result

func load_semantics() -> void:
	semantics.clear();groups.clear()
	if not FileAccess.file_exists(SEMANTICS):return
	var value: Variant=JSON.parse_string(FileAccess.get_file_as_string(SEMANTICS))
	if not value is Dictionary or value.get("version")!=1:return
	if value.get("groups") is Dictionary:
		for key in value["groups"]:
			if key is String and key.length()<=64 and value["groups"][key] is String and value["groups"][key].length()<=80:groups[key]=value["groups"][key]
	if value.get("assets") is Dictionary:
		for id in value["assets"]:
			var entry: Variant=value["assets"][id]
			if not id is String or not entry is Dictionary:continue
			semantics[id]={}
			for field in ["tags","tasks","aliases","use_groups"]:semantics[id][field]=strings(entry.get(field))
			semantics[id]["use_groups"]=semantics[id]["use_groups"].filter(func(key: String):return groups.has(key))
			semantics[id]["source_note"]=entry["source_note"] if entry.get("source_note") is String and entry["source_note"].length()<=1000 else ""

func build(assets: Dictionary) -> void:
	clear();load_semantics()
	for asset in assets.values():prepare(asset)

func use_groups(id: String) -> Array:return semantics.get(id,{}).get("use_groups",[]).duplicate()

func use_matches(id: String,key: String) -> bool:return key.is_empty() or (use_groups(id).is_empty() if key=="unreviewed" else key in use_groups(id))

func subset(ids: Dictionary) -> Dictionary:
	var selected: Dictionary={}
	for id in ids:
		if semantics.has(id):selected[id]=semantics[id]
	return {"version":1,"groups":groups,"assets":selected}


static func words(text: String) -> PackedStringArray:
	var clean: String=""
	for letter in text.left(8192).to_lower():
		var code: int=letter.unicode_at(0)
		if code>=0x300 and code<=0x36f:continue
		if letter=="ß":clean+="ss";continue
		if letter=="œ":clean+="oe";continue
		if letter=="æ":clean+="ae";continue
		var folded: String=letter
		if code>127:
			for i in ACCENTS.size():
				if letter in ACCENTS[i]:folded=LATIN[i];break
		clean+=folded if folded.to_upper()!=folded.to_lower() or folded.is_valid_int() else " "
	return clean.split(" ",false)

static func stem(word: String) -> String:
	if IRREGULAR_PLURALS.has(word):return IRREGULAR_PLURALS[word]
	if word.length() > 4 and word.ends_with("ies"): return word.left(-3) + "y"
	if word.length()>4:
		for ending in ES_ENDINGS:
			if word.ends_with(ending):return word.left(-2)
	if word.length() > 3 and word.ends_with("s") and not word.ends_with("ss"): return word.left(-1)
	return word

static func equivalent(a: String, b: String) -> bool:
	if stem(a) == stem(b): return true
	for group in SYNONYMS:
		if group.has(stem(a)) and group.has(stem(b)): return true
	return false

static func distance(a: String, b: String) -> int:
	# Damerau-Levenshtein includes the common adjacent-letter typing error.
	var rows: Array = []
	for i in a.length() + 1:
		var row: Array[int] = []
		row.resize(b.length() + 1)
		row[0] = i
		rows.append(row)
	for j in b.length() + 1: rows[0][j] = j
	for i in range(1, a.length() + 1):
		for j in range(1, b.length() + 1):
			rows[i][j] = mini(mini(rows[i - 1][j] + 1, rows[i][j - 1] + 1), rows[i - 1][j - 1] + (0 if a[i - 1] == b[j - 1] else 1))
			if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
				rows[i][j] = mini(rows[i][j], rows[i - 2][j - 2] + 1)
	return rows[a.length()][b.length()]

func prepare(asset: Dictionary) -> Dictionary:
	var id: String=asset["id"]
	if index.has(id):return index[id]
	var data: Dictionary=asset.get("data",{});var reviewed: Dictionary=semantics.get(id,{})
	var name: PackedStringArray=words(asset["name"])
	var text: String=id+" "+asset["name"]+" "+asset.get("category","")+" "+asset.get("path","")
	for field in ["source_pack","source_name","source_path","name_source","palette_id","lighting_id"]:text+=" "+str(data.get(field,""))
	for field in ["tags","aliases","theme_labels"]:text+=" "+" ".join(strings(data.get(field)))
	for field in ["tags","tasks","aliases"]:text+=" "+" ".join(reviewed.get(field,[]))
	for group in reviewed.get("use_groups",[]):text+=" "+groups.get(group,group)
	var tokens: Dictionary={}
	for word in words(text):tokens[word]=12 if word in name else 0
	for word in tokens:
		if not postings.has(word):
			postings[word]={}
			var normalized: String=stem(word)
			if not stems.has(normalized):stems[normalized]=[]
			stems[normalized].append(word)
		postings[word][id]=tokens[word]
	index[id]={"name":name,"words":tokens,"id_phrase":" ".join(words(id)),"name_phrase":" ".join(name)}
	queries.clear();return index[id]

static func near_distance(a: String,b: String,limit: int) -> int:
	# Only a narrow diagonal can contribute to an edit distance of one/two.
	# Retain the previous two rows for adjacent-letter transpositions.
	if absi(a.length()-b.length())>limit:return limit+1
	if a.is_empty() or b.is_empty():return maxi(a.length(),b.length())
	var previous:=PackedInt32Array();previous.resize(b.length()+1)
	for j in previous.size():previous[j]=j
	var older: PackedInt32Array=previous
	for i in range(1,a.length()+1):
		var current:=PackedInt32Array();current.resize(b.length()+1);current.fill(limit+1);current[0]=i
		var smallest: int=limit+1
		for j in range(maxi(1,i-limit),mini(b.length(),i+limit)+1):
			current[j]=mini(mini(previous[j]+1,current[j-1]+1),previous[j-1]+(0 if a[i-1]==b[j-1] else 1))
			if i>1 and j>1 and a[i-1]==b[j-2] and a[i-2]==b[j-1]:current[j]=mini(current[j],older[j-2]+1)
			smallest=mini(smallest,current[j])
		if smallest>limit:return limit+1
		older=previous;previous=current
	return previous[b.length()]

func term_matches(term: String) -> Dictionary:
	var result: Dictionary={};var forms: Dictionary={}
	for word in stems.get(stem(term),[]):forms[word]=100 if word==term else 92
	for group in SYNONYMS:
		if stem(term) in group:
			for alternative in group:
				for word in stems.get(stem(alternative),[]):forms[word]=maxi(forms.get(word,0),70)
	for word in postings:
		if word.begins_with(term):forms[word]=maxi(forms.get(word,0),80)
		elif not forms.has(word) and term.length()>=4:
			var limit: int=2 if term.length()>=8 else 1
			if absi(word.length()-term.length())>limit:continue
			var key: String=term+":"+word
			if not scores.has(key):
				if scores.size()>=16384:scores.clear()
				scores[key]=near_distance(term,word,limit)
			if scores[key]<=limit:forms[word]=40-scores[key]*5
	for word in forms:
		for id in postings[word]:result[id]=maxi(result.get(id,0),forms[word]+postings[word][id])
	return result

func query_scores(query: PackedStringArray) -> Dictionary:
	var phrase: String=" ".join(query)
	if queries.has(phrase):return queries[phrase]
	var result: Dictionary={};var first: bool=true
	for term in query:
		var matches: Dictionary=term_matches(term)
		if first:result=matches;first=false
		else:
			for id in result.keys():
				if not matches.has(id):result.erase(id)
				else:result[id]+=matches[id]
		if result.is_empty():break
	for id in result:
		var name: String=index[id]["name_phrase"]
		if index[id]["id_phrase"]==phrase:result[id]+=200000
		elif name==phrase:result[id]+=100000
		elif name.begins_with(phrase):result[id]+=40
		elif phrase in name:result[id]+=20
	if queries.size()>=32:queries.erase(queries.keys()[0])
	queries[phrase]=result;return result

func rank(asset: Dictionary,query: PackedStringArray) -> int:
	prepare(asset)
	return query_scores(query).get(asset["id"],-1) if not query.is_empty() else 0
