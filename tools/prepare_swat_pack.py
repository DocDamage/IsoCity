"""Preserve the HanX SWAT archive and prepare its 114 individual GLBs for Godot."""
import json
import shutil
from pathlib import Path
from ingest_supplemental_assets import SOURCE, RAW, ROOT, REPORT, extract_zip, digest
from prepare_supplemental_assets import res, write

def main():
    archive=SOURCE/'low-poly-swat-pack-hanx-swat-pack.zip'
    extract_zip(archive,RAW/'HanX_SWAT')
    pack=RAW/'HanX_SWAT/HanX_SWAT_Pack'; active=ROOT/'assets/supplemental_models/HanX_SWAT'
    active.mkdir(parents=True,exist_ok=True)
    for notice in ['LICENSE.txt','README.txt']: shutil.copy2(pack/notice,active/notice)
    models={}
    for path in sorted((pack/'GLB').glob('*.glb')):
        key=path.stem
        if key.startswith('_'): continue
        target=active/path.name; shutil.copy2(path,target)
        preview=pack/'Previews'/(key+'.png')
        if not preview.exists(): raise FileNotFoundError(preview)
        shutil.copy2(preview,active/preview.name)
        building=key in ['Building_Guard_Booth','Building_Police_Station','Building_SWAT_HQ','Building_Vehicle_Garage','Building_Watchtower']
        vehicle=key.startswith('Vehicle_') and key not in ['Vehicle_Drone','Vehicle_Police_Helicopter','Vehicle_Bomb_Robot']
        small=key.startswith(('Gear_','Weapon_','SWAT_')) or key in ['Vehicle_Drone','Vehicle_Bomb_Robot']
        architecture=key.startswith(('Training_Wall_','Tile_')) or key in ['Prop_Breach_Door_Frame','Prop_Holding_Cell_Bars','Training_Shooting_Range','Training_Tower']
        behavior={'layer':'Buildings' if building else 'Vehicles' if vehicle else 'Ground' if key.startswith('Tile_') else 'Decorations',
                  'building':building,'vehicle':vehicle,'door':key=='Training_Door','ground':key.startswith('Tile_'),
                  'collision':'none' if small else 'mesh' if architecture else 'box'}
        ident='3d:Supplemental_SWAT/'+key
        models[ident]={'id':ident,'mode':'3d','name':key.replace('_',' '),'category':'Supplemental SWAT',
                       'path':'res://scenes/items_3d/Supplemental_SWAT/'+key+'.tscn','behavior':behavior,
                       'data':{'source_pack':'HanX SWAT','source_name':key,'author':'HanX Assets','license':'HanX Assets Standard License',
                               'source_url':'https://hanx-games.itch.io/','source_export_allowed':False,
                               'source_files':[res(path)],'model_file':res(target),'preview_path':res(active/preview.name),
                               'source_hash':digest(path),'default_scale':1.0,'rigged':key in ['SWAT_Operator','SWAT_Operator_Urban','SWAT_Commander'],
                               'animation_note':'Source provides a rig without animation clips' if key in ['SWAT_Operator','SWAT_Operator_Urban','SWAT_Commander'] else 'Static model'}}
    if len(models)!=114: raise ValueError(f'Expected 114 individual models, found {len(models)}')
    value={'version':1,'items':{},'models':models,'archive_sha256':digest(archive),'notes':['Combined GLB and alternate FBX/OBJ/Blender editions retained in ignored source intake.']}
    write(ROOT/'resources/catalog/swat_registry.json',json.dumps(value,indent=2))
    write(REPORT/'swat_manifest.json',json.dumps(value,indent=2))
    print(f'Prepared {len(models)} HanX SWAT models; source notice preserved.')

if __name__=='__main__': main()
