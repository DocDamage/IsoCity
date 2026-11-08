"""Open allowed I04 exports independently, retaining reviewed names and aliases."""
from pathlib import Path
import os,re,shutil,subprocess,zipfile
from verify_model_previews import port,portable_target
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I04'


def main():
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise RuntimeError('Godot required')
    destination=portable_target(OUT)
    for mode in ('2d','3d'):
        target=destination/mode;target.mkdir(parents=True)
        with zipfile.ZipFile(OUT/f'names_{mode}.zip') as archive:
            for name in archive.namelist():
                if not (target/name).resolve().is_relative_to(target.resolve()):raise ValueError('Unsafe package entry')
            archive.extractall(target)
        assert not (target/'.godot').exists()
        shutil.copyfile(ROOT/'tools/test_reviewed_names_portable.gd',target/'verify_reviewed.gd')
        for stage,args in [('import',['--editor','--import','--quit','--lsp-port',port(),'--dap-port',port()]),('runtime',['--fixed-fps','60','--script','res://verify_reviewed.gd']),('main',['--quit-after','10'])]:
            result=subprocess.run([godot,'--headless','--path',str(target),*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
            log=result.stdout+result.stderr;(OUT/f'portable_{mode}_{stage}.log').write_text(f'Process exit: {result.returncode}\n'+log,encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',log):raise RuntimeError(f'I04 {mode} {stage}: {log[-3000:]}')
            print('PASS: I04 relocated',mode,stage,flush=True)
    print('Retained independent projects:',destination)


if __name__=='__main__':main()
