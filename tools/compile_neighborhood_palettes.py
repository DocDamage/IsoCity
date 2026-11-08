"""Freeze reviewed neighborhood families and optional scenery without editing art."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'resources/catalog/neighborhood_palettes.json'
def read(name):return json.loads((ROOT/'resources/catalog'/name).read_text(encoding='utf-8'))
def compile_catalog():
    zoning=read('zoning_candidates.json');metadata=read('asset_metadata.json')['assets']
    def family_members(family):
        result=sorted(ident for ident,entry in metadata.items() if entry.get('family_id')==family)
        assert result,family
        return result
    well=family_members('supplemental/village/stone_well')
    shrine=family_members('supplemental/village/wayside_shrine')
    choices={
        'hanx_modern':{'label':'HanX modern district','ground':'Sidewalk','road_style':'asphalt','modes':['2d','3d'],
            'parks':['3d:HanX_Park/Tree_Round_Small'],'props':['3d:HanX_Park/Bench_Park','3d:HanX_Park/Lamp_Park'],'prop_density':60,
            'note':'Native HanX homes, shops and schools with matching park furnishings. Models keep their supplied scale in either world.'},
        'korean_street':{'label':'Korean street · limited local use','ground':'Sidewalk','road_style':'asphalt','modes':['2d'],
            'parks':[],'props':[],'prop_density':0,
            'note':'One home and three commercial subjects in 2D. No matching park or street props are supplied; none are substituted. Existing flat 3D cards obscure ground-floor art. Source-project ZIP redistribution is restricted.'},
        'village':{'label':'Village district','ground':'Grass','road_style':'brick','modes':['2d','3d'],
            'parks':well,'props':shrine,'prop_density':35,
            'note':'Supplied village building families and palette appearances. Wells form small shared courtyards; wayside shrines are optional scenery. These are flat sprite cards in 3D.'},
        'industrial':{'label':'Industrial services district','ground':'Sidewalk','road_style':'asphalt','modes':['2d','3d'],
            'parks':[],'props':['3d:HanX_GasStation/Tire_Stack','3d:HanX_GasStation/Oil_Drum'],'prop_density':60,
            'note':'Three supplied vehicle-service building designs and matching yard props. No housing, schools or green parks are invented to fill this limited theme.'},
        'historical':{'label':'Historical village district','ground':'Brick_Pavers','road_style':'brick','modes':['2d','3d'],
            'parks':well,'props':shrine,'prop_density':20,
            'note':'Reviewed historical village families, brick lanes, courtyard wells and occasional wayside shrines. Flat sprite artwork in 3D; no modern fillers.'},
    }
    for key,entry in choices.items():
        groups=[group for group in zoning['families'] if key in group['themes']]
        assert groups,key
        entry['families']=[group['id'] for group in groups]
        entry['2d']=sorted({member for group in groups if '2d' in group['modes'] for member in group['members']})
        entry['3d']=sorted({member for group in groups if '3d' in group['modes'] and '3d' in entry['modes'] for member in group['members']})
        appearances={(metadata[member]['palette_id'],metadata[member]['lighting_id']) for member in entry['2d'] if metadata.get(member,{}).get('appearance_group')=='village'}
        entry['appearances']=[{'palette_id':palette,'lighting_id':lighting} for palette,lighting in sorted(appearances)]
        if appearances:entry['note']+=' The seed chooses one shared palette and lighting appearance for the whole district.'
        entry['revision']=hashlib.sha256(json.dumps({'palette':entry,'zoning_revision':zoning['revision']},sort_keys=True,separators=(',',':')).encode()).hexdigest()
    sources={name:hashlib.sha256((ROOT/'resources/catalog'/name).read_bytes()).hexdigest() for name in ('zoning_candidates.json','asset_metadata.json','asset_behaviors.json','model_grid_bounds.json')}
    return {'version':1,'zoning_revision':zoning['revision'],'sources':sources,'palettes':choices}
def main():
    encoded=json.dumps(compile_catalog(),ensure_ascii=False,sort_keys=True,indent=2)+'\n'
    if '--check' in sys.argv:
        if not DEST.exists() or DEST.read_text(encoding='utf-8')!=encoded:raise SystemExit('Neighborhood palettes are stale; compile them before verification.')
    else:DEST.write_text(encoded,encoding='utf-8')
    print('NEIGHBORHOOD PALETTES: 5 reviewed themes with frozen building families and scenery')
if __name__=='__main__':main()
