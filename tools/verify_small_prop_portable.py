"""Independently import and play both normal and isolated small-prop exports."""
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
from verify_construction_costs_portable import run_import
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/verification/asset_expansion/U18'


def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Set GODOT_BIN to a Godot 4.7+ executable.')
    destination = OUT / 'relocated' / uuid.uuid4().hex
    results = []
    for variant in ('isolated', 'props'):
        for mode in ('2d', '3d'):
            target = destination / variant / mode
            target.mkdir(parents=True)
            package = OUT / f'{variant}_{mode}.zip'
            original_hash = hashlib.sha256(package.read_bytes()).hexdigest()
            expected = OUT / f'expected_{mode}.json'
            with zipfile.ZipFile(package) as archive:
                for name in archive.namelist():
                    if not (target / name).resolve().is_relative_to(target.resolve()):
                        raise RuntimeError(f'Unsafe package entry: {name}')
                manifest = json.loads(archive.read('export-manifest.json'))
                for entry in manifest['files']:
                    content = archive.read(entry['path'])
                    assert len(content) == entry['bytes'] and hashlib.sha256(content).hexdigest() == entry['sha256'], entry['path']
                authored = json.loads(expected.read_text(encoding='utf-8'))['source']
                assert json.loads(archive.read('city-source.json'))['documents'][mode] == authored
                archive.extractall(target)
            assert not (target / '.godot').exists()
            shutil.copyfile(ROOT / 'tools/test_small_prop_export_runtime.gd', target / 'verify_props.gd')
            shutil.copyfile(expected, target / 'expected_props.json')
            original_settings = settings((target / 'project.godot').read_bytes())
            import_args = ([] if '--visible-import' in sys.argv else ['--headless']) + [
                '--editor', '--import', '--lsp-port', port(), '--dap-port', port()]
            if '--import-accessibility-dummy' in sys.argv:
                import_args += ['--accessibility-driver', 'dummy']
            stages = [('import', import_args),
                      ('runtime', ['--headless', '--fixed-fps', '60', '--script', 'res://verify_props.gd']),
                      ('main', ['--headless', '--quit-after', '10'])]
            if '--capture' in sys.argv:
                stages.append(('graphical', ['--fixed-fps', '60', '--script', 'res://verify_props.gd', '--', '--capture']))
            for name, arguments in stages:
                if name == 'import' and os.name == 'nt' and '--visible-import' in sys.argv and '--import-accessibility-dummy' in sys.argv:
                    run_import(godot, target, mode, windows_model_renderer='gl_compatibility', wait_for_windows=True)
                else:
                    stage([godot, '--path', str(target), '--log-file', str(target / f'engine_{name}.log'), *arguments], target, name, 180)
                assert settings((target / 'project.godot').read_bytes()) == original_settings
                assert hashlib.sha256(package.read_bytes()).hexdigest() == original_hash
                log = target / f'verification_{name}.log'
                results.append({'variant': variant, 'mode': mode, 'stage': name, 'log': str(log),
                                'sha256': hashlib.sha256(log.read_bytes()).hexdigest(),
                                'package_sha256': original_hash, 'manifest_files_verified': len(manifest['files'])})
                print(f'PASS: small_prop_portable {variant} {mode} {name}', flush=True)
    (destination / 'portable_projects.json').write_text(json.dumps({'destination': str(destination), 'stages': results}, indent=2) + '\n', encoding='utf-8')
    print(f'Retained independent projects: {destination}')


if __name__ == '__main__':
    main()
