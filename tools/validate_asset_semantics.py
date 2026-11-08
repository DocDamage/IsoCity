"""Validate the reviewed search overlay without changing any source/catalog."""
from pathlib import Path
import json

def validate_semantics(root, known_ids):
    path=Path(root)/'resources/catalog/asset_semantics.json'
    if not path.exists():return
    value=json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(value,dict) or type(value.get('version')) not in (int,float) or value['version']!=1:raise ValueError('Unsupported reviewed semantics version')
    groups=value.get('groups');assets=value.get('assets')
    if not isinstance(groups,dict) or not isinstance(assets,dict):raise ValueError('Reviewed semantics require groups/assets')
    for key,label in groups.items():
        if not isinstance(key,str) or not key or len(key)>64 or key=='unreviewed' or not isinstance(label,str) or not label or len(label)>80:raise ValueError('Invalid reviewed use group')
    for ident,entry in assets.items():
        if ident not in known_ids:raise ValueError('Unknown reviewed semantic asset: '+ident)
        if not isinstance(entry,dict):raise ValueError('Semantic entry must be an object: '+ident)
        if not isinstance(entry.get('source_note'),str) or not entry['source_note'].strip() or len(entry['source_note'])>1000:raise ValueError('Reviewed semantic provenance required: '+ident)
        for field in ('tags','tasks','aliases','use_groups'):
            words=entry.get(field)
            if not isinstance(words,list) or len(words)>64 or any(not isinstance(word,str) or not word.strip() or len(word)>240 for word in words) or len(words)!=len(set(words)):raise ValueError('Invalid semantic '+field+': '+ident)
        if any(group not in groups for group in entry['use_groups']):raise ValueError('Unknown use group: '+ident)
    print(f'Reviewed semantics: {len(assets)} exact assets; {len(groups)} use groups; validated')
