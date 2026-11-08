"""Verify personal placement histories stay outside independently playable exports."""
from pathlib import Path
import hashlib,json,os,re,shutil,subprocess,sys,uuid,zipfile
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U14'
def settings(content):
    """Compare every setting value, allowing the editor's comments/key ordering."""
    result={};section=''
    for line in content.decode('utf-8').splitlines():
        line=line.strip()
        if not line or line.startswith(';'):continue
        if line.startswith('[') and line.endswith(']'):section=line[1:-1];continue
        assert '=' in line,line
        key,value=line.split('=',1);identity=(section,key.strip());assert identity not in result,identity
        result[identity]=value.strip()
    # The normal editor omits these two built-in defaults when saving. The
    # independent runtime also asserts their effective values in both worlds.
    result.setdefault(('rendering','renderer/rendering_method'),'"forward_plus"')
    result.setdefault(('rendering','renderer/rendering_method.mobile'),'"mobile"')
    return result
def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=OUT/'relocated'/uuid.uuid4().hex
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        package=OUT/f'recent_{mode}.zip';package_hash=hashlib.sha256(package.read_bytes()).hexdigest()
        with zipfile.ZipFile(package) as archive:
            names=archive.namelist()
            assert not any('relocated/' in name or 'baseline/' in name or 'preferences.json' in name or 'recent_asset_tools.gd' in name or 'asset_recents.gd' in name or 'studio_recent_assets.json' in name for name in names)
            manifest=json.loads(archive.read('export-manifest.json'))
            assert not any(':Custom/Recent_Local_' in ident for ident in manifest['assets'])
            for name in names:
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_recent_asset_portable.gd',target/'verify_recent.gd');shutil.copyfile(OUT/f'expected_{mode}.json',target/'expected.json')
        project=target/'project.godot';original=project.read_bytes()
        import_args=([] if '--visible-import' in sys.argv else ['--headless','--accessibility','disabled'])+['--editor','--import','--lsp-port',port(),'--dap-port',port()]
        stages=[('import',import_args),('runtime',['--headless','--fixed-fps','60','--script','res://verify_recent.gd']),('main',['--headless','--quit-after','10'])]
        if '--capture' in sys.argv:stages.append(('graphical',['--fixed-fps','60','--script','res://verify_recent.gd','--','--capture']))
        for stage,args in stages:
            # Explicitly selected graphical import uses normal accessibility.
            # Only headless import uses the recorded I13 bridge workaround.
            command=[godot,'--path',str(target),*args];result=subprocess.run(command,cwd=target,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
            log=result.stdout+result.stderr;evidence=f'Process exit: {result.returncode}\nCommand: '+json.dumps(command)+'\n'+log
            (OUT/f'portable_{mode}_{stage}.log').write_text(evidence,encoding='utf-8');(target/f'verification_{stage}.log').write_text(evidence,encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(evidence[-3000:])
            if stage=='import':
                for name in names:
                    if Path(name).suffix.lower() not in ('.glb','.gltf','.png','.svg','.webp','.jpg','.jpeg','.ttf','.otf','.wav','.ogg'):continue
                    remap=(target/(name+'.import')).read_text(encoding='utf-8');dependencies=set(re.findall(r'"res://(\.godot/imported/[^"\n]+)"',remap));assert dependencies,name
                    for dependency in dependencies:assert (target/dependency).is_file() and (target/dependency).stat().st_size>0,dependency
            assert settings(project.read_bytes())==settings(original),'An actual project setting changed'
            assert hashlib.sha256(package.read_bytes()).hexdigest()==package_hash,'Source ZIP changed'
            print('PASS: U14 relocated',mode,stage,flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(destination),'import_surface':'normal graphical editor' if '--visible-import' in sys.argv else 'headless with accessibility disabled'},indent=2)+'\n',encoding='utf-8');print('Retained independent projects:',destination)
if __name__=='__main__':main()
