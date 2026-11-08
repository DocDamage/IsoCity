"""Open each independently imported I14 project with its ordinary native renderer."""
from pathlib import Path
import hashlib,json,os,sys
from verify_collection_portable import stage
from verify_companion_portable import settings
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I14'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    engine=os.environ['GODOT_BIN'];evidence=json.loads((OUT/'portable_projects.json').read_text(encoding='utf-8'));base=Path(evidence['destination']);results=[]
    assert len(evidence['results'])==18 and base.is_relative_to(Path(r'F:\dev\IsoCity-portable-validation\I14'))
    for mode in ['2d','3d']:
      for kind in ['stairs','elevator','legacy']:
        name=f'{kind}_{mode}';target=base/name;project=target/'project.godot';before=settings(project.read_bytes());package=OUT/'exports'/f'{name}.zip';package_sha=sha(package)
        stage([engine,'--path',str(target),'--log-file',str(target/'engine_visible_main.log'),'--disable-vsync','--quit-after','30'],target,'visible_main',90)
        assert settings(project.read_bytes())==before and sha(package)==package_sha
        results.append({'package':name,'log':str(target/'verification_visible_main.log'),'sha256':sha(target/'verification_visible_main.log'),'native_renderer':True})
        print(f'PASS: resident_activity_visible {name}',flush=True)
    (OUT/'portable_visible.json').write_text(json.dumps({'destination':str(base),'results':results,'configuration':'ordinary package rendering and accessibility; command-line vsync disabled only'},indent=2)+'\n',encoding='utf-8')
if __name__=='__main__':main()
