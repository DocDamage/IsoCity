"""Refresh measured prepared-model style facts with the installed Godot engine."""
from pathlib import Path
import argparse,os,re,shutil,subprocess
ROOT=Path(__file__).resolve().parents[1]

def compile_styles(root=ROOT,check=False):
    script=root/'tools/compile_asset_style_models.gd'
    if not script.exists():return
    godot=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:raise ValueError('Godot is required to measure prepared style evidence')
    command=[godot,'--headless','--path',str(root),'--script','res://tools/compile_asset_style_models.gd']
    if check:command+=['--','--check']
    result=subprocess.run(command,cwd=root,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=180)
    output=result.stdout+result.stderr
    if result.returncode or re.search(r'(?m)^(ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)',output):raise ValueError('Prepared style measurement failed:\n'+output[-4000:])
    print(output.strip())

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');compile_styles(check=parser.parse_args().check)
