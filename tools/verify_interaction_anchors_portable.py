"""Verify interaction anchors and station reservations in independent playable exports."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,uuid,zipfile
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I07'

def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        with zipfile.ZipFile(OUT/f'anchors_{mode}.zip') as archive:
            names=archive.namelist()
            assert 'scripts/builder/activity_reservations.gd' in names
            assert not any('relocated/' in name or 'baseline/' in name for name in names)
            for name in names:
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_interaction_anchors_portable.gd',target/'verify_anchors.gd')
        shutil.copyfile(OUT/f'expected_{mode}.json',target/'expected.json')
        # Wait on the editor filesystem, not an elapsed frame count. The
        # temporary observer uses the ordinary editor/SceneTree and is removed
        # before runtime validation. Original project settings are restored
        # byte-for-byte even when the editor fails. No error is accepted/retried.
        plugin=target/'addons/isocity_verify_import';plugin.mkdir(parents=True)
        shutil.copyfile(ROOT/'tools/portable_import_wait.gd',plugin/'plugin.gd')
        (plugin/'plugin.cfg').write_text('[plugin]\nname="Import verification"\ndescription="Wait for completed imports"\nauthor="IsoCity verification"\nversion="1.0"\nscript="plugin.gd"\n',encoding='utf-8')
        project=target/'project.godot';original=project.read_bytes()
        assert b'[editor_plugins]' not in original
        project.write_bytes(original+b'\n[editor_plugins]\nenabled=PackedStringArray("res://addons/isocity_verify_import/plugin.cfg")\n')
        for stage,args in [('import',['--editor','--max-fps','60','--lsp-port',port(),'--dap-port',port()]),('runtime',['--fixed-fps','60','--script','res://verify_anchors.gd']),('main',['--quit-after','10'])]:
            command=[godot,'--headless','--path',str(target),*args]
            try:
                result=subprocess.run(command,cwd=target,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
            finally:
                if stage=='import':
                    project.write_bytes(original)
                    assert plugin.resolve().is_relative_to(target.resolve())
                    for name in ('plugin.gd','plugin.gd.uid','plugin.cfg'):(plugin/name).unlink(missing_ok=True)
                    plugin.rmdir()
                    if not any((target/'addons').iterdir()):(target/'addons').rmdir()
            log=result.stdout+result.stderr;(OUT/f'portable_{mode}_{stage}.log').write_text(f'Process exit: {result.returncode}\nCommand: '+json.dumps(command)+'\n'+log,encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(f'I07 {mode} {stage}: {log[-3000:]}')
            if stage=='import':
                assert 'Editor imports complete; filesystem stable for two seconds.' in log
                assert list((target/'.godot/imported').glob('Student_Chair.glb-*.scn')),'Prepared model import did not complete'
                assert project.read_bytes()==original and not plugin.exists()
            print('PASS: I07 relocated',mode,stage,flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(destination)},indent=2)+'\n')
    print('Retained independent projects:',destination)

if __name__=='__main__':main()
