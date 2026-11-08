"""Import zoning projects on F: and verify every host-side future candidate."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import sys
import uuid
import zipfile
from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/verification/asset_expansion/I15'

def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot is required')
    destination = OUT / 'relocated' / uuid.uuid4().hex
    village = '--village' in sys.argv
    variant = '_village' if village else ''
    evidence = []
    for mode in ('2d', '3d'):
        target = destination / mode
        target.mkdir(parents=True)
        package = ROOT / 'output' / f'zoning{variant}_{mode}.zip'
        package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
        with zipfile.ZipFile(package) as archive:
            for name in archive.namelist():
                if not (target / name).resolve().is_relative_to(target.resolve()):
                    raise RuntimeError(f'Unsafe archive entry: {name}')
            archive.extractall(target)
        assert not (target / '.godot').exists(), 'Import cache was included'
        shutil.copyfile(ROOT / 'tools/test_zone_export_runtime.gd', target / 'verify_zone.gd')
        shutil.copyfile(OUT / f'zone_expectation{variant}_{mode}.json', target / 'zone_expectation.json')
        original_settings = settings((target / 'project.godot').read_bytes())
        import_args = ([] if '--visible-import' in sys.argv else ['--headless']) + ['--editor', '--import', '--lsp-port', port(), '--dap-port', port()]
        if '--import-accessibility-dummy' in sys.argv:
            import_args += ['--accessibility-driver', 'dummy']
        stages = [('import', import_args, 180),
                  ('runtime', ['--headless', '--fixed-fps', '60', '--script', 'res://verify_zone.gd'], 180),
                  ('main', ['--headless', '--quit-after', '10'], 60)]
        if "--capture" in sys.argv:
            stages.append(("graphical", ["--fixed-fps", "60", "--script", "res://verify_zone.gd", "--", "--capture"], 180))
        for name, arguments, timeout in stages:
            stage([godot, '--path', str(target), '--log-file', str(target / f'engine_{name}.log'), *arguments], target, name, timeout)
            assert settings((target / 'project.godot').read_bytes()) == original_settings
            assert hashlib.sha256(package.read_bytes()).hexdigest() == package_hash
            evidence.append({'mode': mode, 'stage': name, 'log': str(target / f'verification_{name}.log')})
            print(f'PASS: zoning {mode} {name}', flush=True)
    (OUT / f'portable_projects{variant}.json').write_text(json.dumps({'destination': str(destination), 'stages': evidence,
        'import_surface': 'graphical' if '--visible-import' in sys.argv else 'headless',
        'import_accessibility_driver': 'dummy' if '--import-accessibility-dummy' in sys.argv else 'default'}, indent=2) + '\n', encoding='utf-8')
    print(f'Zoning projects retained: {destination}')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
