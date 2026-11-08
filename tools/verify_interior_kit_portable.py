"""Verify explicitly applied owned/standalone room kits after independent import."""
from pathlib import Path
import json,os,re,shutil,sys,uuid,zipfile
from verify_collection_portable import stage
from verify_construction_costs_portable import run_import
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U13'

def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for case in ('owned','room'):
        for mode in ('2d','3d'):
            target=destination/case/mode;target.mkdir(parents=True)
            with zipfile.ZipFile(OUT/f'{case}_{mode}.zip') as archive:
                names=archive.namelist()
                assert {'city-source.json','scripts/builder/interior_kits.gd','resources/catalog/interior_kits.json'}.issubset(names)
                assert not any('baseline/' in name or 'relocated/' in name or 'preferences.json' in name or 'interior_kit_tools.gd' in name or 'interior_kit_preview.gd' in name for name in names)
                manifest=json.loads(archive.read('export-manifest.json'))
                for ident in manifest['assets']:
                    if ident.startswith('3d:HanX_'):assert 'resources/previews_3d/'+ident.removeprefix('3d:')+'.png' in names
                for name in names:
                    if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
                archive.extractall(target)
            assert not (target/'.godot').exists()
            shutil.copyfile(ROOT/'tools/test_interior_kit_portable.gd',target/'verify_kit.gd')
            shutil.copyfile(OUT/f'expected_{case}_{mode}.json',target/'expected.json')
            project=target/'project.godot';original=project.read_bytes()
            run_import(godot,target,mode,windows_model_renderer='gl_compatibility',
                       wait_for_windows=True,headless_observer=True)
            for name in names:
                if Path(name).suffix.lower() not in ('.glb','.gltf','.png','.svg','.webp','.jpg','.jpeg','.ttf','.otf','.wav','.ogg'):continue
                remap=(target/(name+'.import')).read_text(encoding='utf-8');dependencies=set(re.findall(r'"res://(\.godot/imported/[^"\n]+)"',remap));assert dependencies,name
                for dependency in dependencies:assert (target/dependency).is_file() and (target/dependency).stat().st_size>0,dependency
            assert project.read_bytes()==original
            print('PASS: U13 relocated',case,mode,'import',flush=True)
            stages=[('runtime',['--headless','--fixed-fps','60','--script','res://verify_kit.gd']),('main',['--headless','--quit-after','10'])]
            if '--capture' in sys.argv:stages.append(('graphical',['--fixed-fps','60','--script','res://verify_kit.gd','--','--capture']))
            for label,args in stages:
                stage([godot,'--path',str(target),*args],target,label,240)
                assert project.read_bytes()==original
                print('PASS: U13 relocated',case,mode,label,flush=True)
    (destination/'portable_projects.json').write_text(json.dumps({'destination':str(destination)},indent=2)+'\n',encoding='utf-8')
    print('Retained independent projects:',destination)

if __name__=='__main__':main()
