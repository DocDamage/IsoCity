"""Fresh independent export verification for individually selected furnishings."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,uuid,zipfile
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U02'

def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        with zipfile.ZipFile(OUT/f'selected_{mode}.zip') as archive:
            names=archive.namelist()
            assert 'scripts/builder/task_collections.gd' in names and 'resources/catalog/task_collections.json' in names
            assert not any('Camping_gear' in name or 'relocated/' in name or 'baseline/' in name or 'preferences.json' in name for name in names)
            for name in names:
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_task_collections_portable.gd',target/'verify_tasks.gd')
        shutil.copyfile(OUT/f'expected_{mode}.json',target/'expected.json')
        original=(target/'project.godot').read_bytes()
        for stage,args in [('import',['--editor','--import','--accessibility','disabled','--lsp-port',port(),'--dap-port',port()]),('runtime',['--fixed-fps','60','--script','res://verify_tasks.gd']),('main',['--quit-after','10'])]:
            # The import-only bridge flag is the explicit I13 native-exit
            # workaround. Runtime/main/graphical checks keep project defaults.
            command=[godot,'--headless','--path',str(target),*args]
            result=subprocess.run(command,cwd=target,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
            log=result.stdout+result.stderr;evidence=f'Process exit: {result.returncode}\nCommand: '+json.dumps(command)+'\n'+log
            (OUT/f'portable_{mode}_{stage}.log').write_text(evidence,encoding='utf-8');(target/f'verification_{stage}.log').write_text(evidence,encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(evidence[-2500:])
            if stage=='import':
                for name in names:
                    if Path(name).suffix.lower() not in ('.glb','.gltf','.png','.svg','.webp','.jpg','.jpeg','.ttf','.otf','.wav','.ogg'):continue
                    remap=(target/(name+'.import')).read_text(encoding='utf-8');dependencies=set(re.findall(r'"res://(\.godot/imported/[^"\n]+)"',remap));assert dependencies,name
                    for dependency in dependencies:assert (target/dependency).is_file() and (target/dependency).stat().st_size>0,dependency
            assert (target/'project.godot').read_bytes()==original
            print('PASS: U02 relocated',mode,stage,flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(destination)},indent=2)+'\n')
    print('Retained independent projects:',destination)

if __name__=='__main__':main()
