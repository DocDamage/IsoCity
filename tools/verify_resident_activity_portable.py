"""Import and run I14 packages outside the checkout, preserving their settings."""
from pathlib import Path
import hashlib,json,os,shutil,sys,uuid,zipfile
from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'output/verification/asset_expansion/I14'
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    engine=os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not engine:raise RuntimeError('Set GODOT_BIN to Godot 4.7+.')
    destination=Path(r'F:\dev\IsoCity-portable-validation\I14')/uuid.uuid4().hex
    results=[]
    for mode in ('2d','3d'):
      for kind in ('stairs','elevator','legacy'):
        name=f'{kind}_{mode}';target=destination/name;target.mkdir(parents=True)
        package=OUT/'exports'/f'{name}.zip';package_hash=digest(package)
        with zipfile.ZipFile(package) as archive:
          names=archive.namelist();manifest=json.loads(archive.read('export-manifest.json'))
          for entry in manifest['files']:
            data=archive.read(entry['path']);assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],entry['path']
          for path in names:
            if not (target/path).resolve().is_relative_to(target.resolve()):raise RuntimeError(f'Unsafe package entry {path}')
          assert not any('.godot/' in p or '/output/' in p or p.startswith('output/') for p in names)
          for script in ('resident_activity_runtime','resident_activity_plan','resident_activities','resident_activity_view','resident_floor_travel','resident_stair_state','resident_stair_travel','resident_elevator_state','interior_visit_revision'):
            assert f'scripts/builder/{script}.gd' in names,script
          assert '[node name="CitizenActors"' not in archive.read('city.tscn').decode('utf-8')
          archive.extractall(target)
        expected=json.loads((OUT/'exports'/f'{name}_expected.json').read_text(encoding='utf-8'));expected['source_root']=ROOT.as_posix()
        (target/'expected_activities.json').write_text(json.dumps(expected,indent=2)+'\n',encoding='utf-8')
        shutil.copyfile(ROOT/'tools/test_resident_activity_export_runtime.gd',target/'verify_activities.gd')
        assert not (target/'.godot').exists()
        project=target/'project.godot';original_settings=settings(project.read_bytes())
        # Visible editor import can crash natively on this Windows driver.
        # Import headlessly; runtime/main retain ordinary accessibility settings.
        stages=[('import',['--headless','--editor','--import','--accessibility-driver','dummy','--lsp-port',port(),'--dap-port',port()]),
                ('runtime',['--headless','--fixed-fps','60','--script','res://verify_activities.gd']),
                ('main',['--headless','--quit-after','10'])]
        for label,args in stages:
          stage([engine,'--path',str(target),'--log-file',str(target/f'engine_{label}.log'),*args],target,label,180)
          assert settings(project.read_bytes())==original_settings
          assert digest(package)==package_hash
          results.append({'package':name,'stage':label,'log':str(target/f'verification_{label}.log'),'sha256':digest(target/f'verification_{label}.log')})
          print(f'PASS: resident_activity_portable {name} {label}',flush=True)
    (OUT/'portable_projects.json').write_text(json.dumps({'destination':str(destination),'results':results,'native_import_workaround':'headless editor import with accessibility-driver dummy after retained visible-editor native crashes; no package/runtime preference change'},indent=2)+'\n',encoding='utf-8')
    print(f'Retained independent projects: {destination}',flush=True)
if __name__=='__main__':main()
