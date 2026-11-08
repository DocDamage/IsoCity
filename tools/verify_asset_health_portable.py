"""Verify thumbnail health and dependencies in independent playable exports."""
from pathlib import Path
import hashlib,json,os,shutil,uuid,zipfile
from verify_collection_portable import stage
from verify_construction_costs_portable import run_import
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U17'

def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        with zipfile.ZipFile(OUT/f'health_{mode}.zip') as archive:
            facts=json.loads(archive.read('resources/catalog/asset_style_models.json'))
            required={'3d:HanX_School/Student_Chair','3d:Supplemental_Spaceships_II/belly_bay_bomber'}
            room={'3d:HanX_Shop/'+name for name in ('Cafe_Counter','Cafe_Table_Set','Floor_Tile_Store','Pastry_Display','Planter_Box','Shelf_Wall','Wall_Store_Segment')} if mode=='3d' else set()
            assert set(facts['assets'])==required|room,'Only authored models and normal room-template dependencies belong in this package'
            expected={'models':sorted(required|room),'previews':{}}
            descriptor=json.loads(archive.read('resources/catalog/supplemental_registry.json'))['models']['3d:Supplemental_Spaceships_II/belly_bay_bomber']
            for ident in required|room:
                preview=descriptor['data']['preview_path'].removeprefix('res://') if ident.startswith('3d:Supplemental_') else 'resources/previews_3d/'+ident.removeprefix('3d:')+'.png'
                assert preview in archive.namelist(),'Default native and repaired/supplied previews must be retained: '+ident
                expected['previews'][ident]={'path':'res://'+preview,'sha256':hashlib.sha256(archive.read(preview)).hexdigest()}
            assert 'workflow_preview.png' in expected['previews']['3d:Supplemental_Spaceships_II/belly_bay_bomber']['path']
            assert not any('.isocity-preview.json' in name or '.partial' in name or 'backups/' in name or name.endswith(('asset_health_tools.gd','asset_preview_repair.gd','model_thumbnail.gd')) for name in archive.namelist()),'Private repair UI/cache/backups never enter the package'
            for name in archive.namelist():
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_asset_health_portable.gd',target/'verify_health.gd')
        (target/'expected_health.json').write_text(json.dumps(expected),encoding='utf-8')
        shutil.copyfile(ROOT/'scripts/builder/asset_health.gd',target/'verify_asset_health.gd')
        authored=json.loads((OUT/f'health_{mode}.isocity.json').read_text(encoding='utf-8'))
        (target/'expected_health_objects.json').write_text(json.dumps(authored['documents'][mode]['objects']) if 'documents' in authored else json.dumps(authored),encoding='utf-8')
        project=target/'project.godot'
        original=project.read_bytes()
        run_import(godot,target,mode,windows_model_renderer='gl_compatibility',
                   wait_for_windows=True,headless_observer=True)
        assert list((target/'.godot/imported').glob('belly_bay_bomber.glb-*.scn')),'Prepared model import did not complete'
        assert project.read_bytes()==original and not (target/'addons/isocity_verify_import').exists()
        print('PASS: U17 relocated',mode,'import',flush=True)
        for label,args in [('runtime',['--fixed-fps','60','--script','res://verify_health.gd']),('main',['--quit-after','10'])]:
            command=[godot,'--headless','--path',str(target),*args]
            stage(command,target,label,180)
            print('PASS: U17 relocated',mode,label,flush=True)
    (destination/'portable_projects.json').write_text(json.dumps({'destination':str(destination)},indent=2)+'\n',encoding='utf-8')
    print('Retained independent projects:',destination)

if __name__=='__main__':main()
