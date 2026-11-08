"""Verify starter interiors and future room dependencies in independent playable exports."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,uuid,zipfile
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I13'

def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for case in ('kits','lazy','empty'):
        for mode in ('2d','3d'):
            target=destination/case/mode;target.mkdir(parents=True)
            with zipfile.ZipFile(OUT/f'{case}_{mode}.zip') as archive:
                names=archive.namelist()
                assert {'scripts/builder/activity_reservations.gd','scripts/builder/interior_kits.gd','resources/catalog/interior_kits.json'}.issubset(names)
                assert ('scenes/items_3d/HanX_School/Student_Chair.tscn' in names)==(case!='empty')
                assert ('scenes/items_3d/HanX_GasStation/Workbench.tscn' in names)==(case=='kits')
                manifest=json.loads(archive.read('export-manifest.json'))
                for ident in manifest['assets']:
                    if ident.startswith('3d:HanX_'):assert 'resources/previews_3d/'+ident.removeprefix('3d:')+'.png' in names
                assert not any('relocated/' in name or 'baseline/' in name for name in names)
                for name in names:
                    if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
                archive.extractall(target)
            assert not (target/'.godot').exists()
            shutil.copyfile(ROOT/'tools/test_interior_kits_portable.gd',target/'verify_kits.gd')
            shutil.copyfile(OUT/(f'expected_{mode}.json' if case=='kits' else f'expected_{case}_{mode}.json'),target/'expected.json')
            project=target/'project.godot';original=project.read_bytes()
            assert b'[editor_plugins]' not in original
            # Native --import waits for imports itself. No verification addon or
            # modified project settings participate in editor shutdown. Validate
            # every source's generated import files before testing the runtime.
            # Headless imports have no screen-reader surface. Isolate the native
            # accessibility bridge here; runtime and graphical checks keep the
            # project's default accessibility behavior. This does not alter ZIPs.
            for stage,args in [('import',['--editor','--import','--accessibility','disabled','--lsp-port',port(),'--dap-port',port()]),('runtime',['--fixed-fps','60','--script','res://verify_kits.gd']),('main',['--quit-after','10'])]:
                command=[godot,'--headless','--path',str(target),*args]
                result=subprocess.run(command,cwd=target,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
                log=result.stdout+result.stderr
                evidence=f'Process exit: {result.returncode}\nCommand: '+json.dumps(command)+'\n'+log
                (OUT/f'portable_{case}_{mode}_{stage}.log').write_text(evidence,encoding='utf-8')
                # Keep each attempt's exact exit/log with its project, including
                # incomplete runs. A later fresh run cannot erase a native fault.
                (target/f'verification_{stage}.log').write_text(evidence,encoding='utf-8')
                if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(f'I13 {case} {mode} {stage}: {log[-3000:]}')
                if stage=='import':
                    assert list((target/'.godot/imported').glob('School_Building.glb-*.scn')),'Prepared model import did not complete'
                    for name in names:
                        if Path(name).suffix.lower() not in ('.glb','.gltf','.png','.jpg','.jpeg','.svg','.webp','.wav','.ogg','.ttf','.otf'):continue
                        remap=(target/(name+'.import')).read_text(encoding='utf-8')
                        dependencies=set(re.findall(r'"res://(\.godot/imported/[^"\n]+)"',remap))
                        assert dependencies,f'Missing imported result: {name}'
                        for dependency in dependencies:assert (target/dependency).is_file() and (target/dependency).stat().st_size>0,dependency
                    assert project.read_bytes()==original and not (target/'addons/isocity_verify_import').exists()
                print('PASS: I13 relocated',case,mode,stage,flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(destination)},indent=2)+'\n')
    print('Retained independent projects:',destination)

if __name__=='__main__':main()
