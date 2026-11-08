"""Validate reviewed companion identities and apply their explicit behavior override."""
from pathlib import Path
import argparse,json,math
ROOT=Path(__file__).resolve().parents[1]
def compile_companions(root=ROOT,check=False):
    catalog=root/'resources/catalog';rules=json.loads((catalog/'asset_companions.json').read_text(encoding='utf-8'))
    metadata=json.loads((catalog/'asset_metadata.json').read_text(encoding='utf-8'))['assets']
    assert type(rules.get('version')) is int and rules['version']==1
    assert isinstance(rules.get('relationships'),dict) and 0<len(rules['relationships'])<=32
    seen=set()
    for key,entry in rules['relationships'].items():
        assert isinstance(key,str) and 0<len(key)<=80
        assert entry['source'] in metadata and entry['source'] not in seen;seen.add(entry['source'])
        for field,limit in [('label',120),('source_set',120),('note',320)]:assert isinstance(entry[field],str) and 0<len(entry[field])<=limit
        assert isinstance(entry['companions'],list) and 0<len(entry['companions'])<=4
        assert type(entry['related_overlap']) is bool
        for member in entry['companions']:
            assert member['asset'] in metadata and member['asset']!=entry['source']
            assert isinstance(member['offset'],list) and len(member['offset'])==3
            assert all(type(x) in (int,float) and math.isfinite(x) and abs(x)<=64 for x in member['offset'])
            assert type(member['yaw']) in (int,float) and math.isfinite(member['yaw']) and abs(member['yaw'])<=360
        assert isinstance(entry['clearance'],list) and len(entry['clearance'])<=16
        for point in entry['clearance']:assert isinstance(point,list) and len(point)==3 and all(type(x) in (int,float) and math.isfinite(x) and abs(x)<=64 for x in point)
        if 'coverage_box' in entry:
            coverage=entry['coverage_box'];assert isinstance(coverage,dict) and isinstance(coverage.get('half_span'),list) and len(coverage['half_span'])==2
            assert all(type(x) in (int,float) and math.isfinite(x) and .01<=x<=64 for x in coverage['half_span']+[coverage['height']])
    path=catalog/'asset_behaviors.json';behavior=json.loads(path.read_text(encoding='utf-8'))
    for ident,override in rules['behavior_overrides'].items():
        assert ident in metadata and ident in behavior
        assert set(override)=={'collision'} and override['collision'] in ('mesh','box','none')
        if check:assert all(behavior[ident].get(key)==value for key,value in override.items()),f'Stale companion behavior: {ident}'
        else:behavior[ident].update(override)
    if not check:path.write_text(json.dumps(behavior,indent='\t',sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8')
    path=catalog/'props.json';props=json.loads(path.read_text(encoding='utf-8'))
    for ident,override in rules.get('prop_overrides',{}).items():
        assert ident in metadata and ident in props['assets']
        assert set(override).issubset({'approach','exit','anchor_review'})
        for key in ('approach','exit'):
            point=override[key];assert isinstance(point,list) and len(point)==3 and all(type(x) in (int,float) and math.isfinite(x) and abs(x)<=64 for x in point)
        if check:assert all(props['assets'][ident].get(key)==value for key,value in override.items()),f'Stale companion station anchors: {ident}'
        else:props['assets'][ident].update(override)
    if not check:path.write_text(json.dumps(props,indent='\t',sort_keys=True,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f"Companions: {len(seen)} reviewed relationships; explicit behavior overrides {'checked' if check else 'applied'}")
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');compile_companions(check=parser.parse_args().check)
