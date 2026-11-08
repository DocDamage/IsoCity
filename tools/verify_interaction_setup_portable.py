"""Verify current prop/pose runtime independently after U12 planner extraction."""
from pathlib import Path
import hashlib,json,os,shutil,uuid,zipfile
from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'output/verification/asset_expansion/U12'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    engine=os.environ['GODOT_BIN'];base=Path(r'F:\dev\IsoCity-portable-validation\U12')/uuid.uuid4().hex;results=[]
    for mode in ('2d','3d'):
        target=base/mode;target.mkdir(parents=True)
        package=OUT/'exports'/f'props_{mode}.zip';package.parent.mkdir(exist_ok=True)
        if not package.exists():shutil.copyfile(ROOT/'output'/package.name,package)
        digest=sha(package)
        with zipfile.ZipFile(package) as z:
            names=z.namelist();assert not any('.godot/' in n or 'interaction_setup_' in n for n in names)
            for n in names:assert (target/n).resolve().is_relative_to(target.resolve()),n
            for entry in json.loads(z.read('export-manifest.json'))['files']:
                data=z.read(entry['path']);assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],entry['path']
            for n in ['scripts/builder/prop_plan.gd','scripts/builder/prop_runtime.gd','scripts/character_animation.gd']:
                assert hashlib.sha256(z.read(n)).hexdigest()==sha(ROOT/n),n
            assert 'message_key' not in z.read('city-source.json').decode('utf-8')
            z.extractall(target)
        shutil.copyfile(ROOT/'tools/test_props_export_runtime.gd',target/'verify_props.gd')
        project=target/'project.godot';before=settings(project.read_bytes())
        for name,arguments in [('import',['--headless','--editor','--import','--accessibility-driver','dummy','--lsp-port',port(),'--dap-port',port()]),('runtime',['--headless','--fixed-fps','60','--script','res://verify_props.gd']),('visible_main',['--disable-vsync','--quit-after','30'])]:
            stage([engine,'--path',str(target),'--log-file',str(target/f'engine_{name}.log'),*arguments],target,name,180)
            assert settings(project.read_bytes())==before and sha(package)==digest
            log=target/f'verification_{name}.log';results.append({'mode':mode,'stage':name,'log':str(log),'sha256':sha(log),'package_sha256':digest});print(f'PASS: interaction_setup_portable {mode} {name}',flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(base),'results':results},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
