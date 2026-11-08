"""Open allowed U01 exports independently, retaining browse themes."""
from pathlib import Path
import json,os,re,shutil,subprocess,zipfile
from verify_model_previews import port,portable_target
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/U01'


def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=portable_target(OUT)
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        with zipfile.ZipFile(OUT/f'themes_{mode}.zip') as archive:
            for name in archive.namelist():
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_asset_themes_portable.gd',target/'verify_reviewed.gd')
        # --import already waits for imports and quits. --quit asks for exit
        # after the first iteration and must not compete with that lifecycle.
        for stage,args in [('import',['--import','--lsp-port',port(),'--dap-port',port()]),('runtime',['--fixed-fps','60','--script','res://verify_reviewed.gd']),('main',['--quit-after','10'])]:
            command=[godot,'--headless','--path',str(target),*args]
            result=subprocess.run(command,cwd=target,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
            log=result.stdout+result.stderr;(OUT/f'portable_{mode}_{stage}.log').write_text(f'Process exit: {result.returncode}\nCommand: '+json.dumps(command)+'\n'+log,encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(f'U01 {mode} {stage}: {log[-3000:]}')
            print('PASS: U01 relocated',mode,stage,flush=True)
    print('Retained independent projects:',destination)


if __name__=='__main__':main()
