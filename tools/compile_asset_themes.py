"""Compile reviewed browse collections without changing gameplay or asset IDs."""
from pathlib import Path
import argparse
import json
from prepare_supplemental_assets import write
ROOT=Path(__file__).resolve().parents[1]
THEMES=('hanx_modern','pixel_city','village','industrial','space','historical')

def catalog_assets(root):
    assets={};models={}
    for filename in ('catalog_registry.json','imported_registry.json','supplemental_registry.json','swat_registry.json','reviewed_registry.json'):
        path=root/'resources/catalog'/filename
        if not path.exists():continue
        raw=json.loads(path.read_text(encoding='utf-8'))
        for ident,item in raw.get('items',{}).items():
            pack=item.get('source_pack')
            if not pack:pack='RPG World' if 'isometric_rpg_world/' in str(item.get('directions',{})) else 'Pixel Isometric'
            assets['2d:'+ident]={'pack':pack,'category':item['category']}
        models.update(raw.get('models',{}))
    for scene in sorted((root/'scenes/items_3d').glob('*/*.tscn')):
        ident='3d:'+scene.relative_to(root/'scenes/items_3d').with_suffix('').as_posix()
        descriptor=models.get(ident,{})
        assets[ident]={'pack':descriptor.get('data',{}).get('source_pack',scene.parent.name),'category':descriptor.get('category',scene.parent.name.removeprefix('HanX_').replace('_',' '))}
    return assets

def tags(value):
    if not isinstance(value,list) or any(not isinstance(v,str) or v not in THEMES for v in value) or len(set(value))!=len(value):
        raise ValueError('Invalid or duplicate reviewed theme tags')
    return [theme for theme in THEMES if theme in value]

def compile_themes(root=ROOT,check=False):
    catalog=root/'resources/catalog';source=catalog/'asset_themes.json'
    manifest=json.loads(source.read_text(encoding='utf-8'))
    if not isinstance(manifest,dict) or type(manifest.get('version')) is not int or manifest['version']!=1:
        raise ValueError('Unsupported theme manifest')
    definitions=manifest.get('definitions')
    if not isinstance(definitions,dict) or set(definitions)!=set(THEMES):raise ValueError('Theme definitions must contain the six supported collections')
    for theme,definition in definitions.items():
        if not isinstance(definition,dict) or any(not isinstance(definition.get(k),str) or not definition[k].strip() for k in ('label','description','icon','preview_id')):
            raise ValueError('Invalid theme definition: '+theme)
    assets=catalog_assets(root);packs={asset['pack'] for asset in assets.values()}
    rules=manifest.get('packs');overrides=manifest.get('assets',{})
    if not isinstance(rules,dict) or not isinstance(overrides,dict):raise ValueError('Invalid theme rules')
    output={}
    for pack,rule in rules.items():
        if pack not in packs:raise ValueError('Unknown reviewed theme source group: '+pack)
        if not isinstance(rule,dict) or not isinstance(rule.get('note'),str) or not rule['note'].strip():raise ValueError('Missing theme review note: '+pack)
        tags(rule.get('themes'))
    for ident,asset in assets.items():
        rule=rules.get(asset['pack'],{'themes':[],'note':'No reviewed theme assignment for this source group yet.'})
        output[ident]={'themes':tags(rule['themes']),'theme_note':rule['note']}
    for ident,rule in overrides.items():
        if ident not in assets:raise ValueError('Unknown reviewed theme asset: '+ident)
        if not isinstance(rule,dict) or not isinstance(rule.get('note'),str) or not rule['note'].strip():raise ValueError('Missing asset-theme review note: '+ident)
        output[ident]={'themes':tags(rule.get('themes')),'theme_note':rule['note']}
    for theme,definition in definitions.items():
        if definition['preview_id'] not in assets or theme not in output[definition['preview_id']]['themes']:
            raise ValueError('Theme preview is not a member: '+theme)
    result={'version':1,'assets':dict(sorted(output.items()))}
    content=json.dumps(result,ensure_ascii=False,indent=2)+'\n';destination=catalog/'asset_theme_metadata.json'
    if check:
        if not destination.exists() or destination.read_text(encoding='utf-8')!=content:raise ValueError('Theme metadata is stale; run tools/compile_asset_themes.py')
    else:write(destination,content)
    print('Asset themes:',len(output),'assets;',sum(not v['themes'] for v in output.values()),'unclassified;', 'checked' if check else 'compiled')
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');compile_themes(check=parser.parse_args().check)
