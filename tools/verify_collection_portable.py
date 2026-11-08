"""Import and play project palettes from fresh, relocated source packages."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import uuid
import zipfile

from verify_companion_portable import settings
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/verification/asset_expansion/U15'


def stage(command, target, name, timeout):
    log_path = target / f'verification_{name}.log'
    with log_path.open('w', encoding='utf-8') as log:
        log.write('Command: ' + json.dumps(command) + '\n')
        log.flush()
        process = subprocess.Popen(command, cwd=target, stdout=log, stderr=subprocess.STDOUT,
                                   creationflags=subprocess.CREATE_NO_WINDOW if os.name == 'nt' else 0)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'nt':
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], stdout=log, stderr=subprocess.STDOUT)
            else:
                process.kill()
            process.wait()
            raise RuntimeError(f'{name} timed out; retained {log_path}')
        log.write(f'\nProcess exit: {code}\n')
    text = log_path.read_text(encoding='utf-8', errors='replace')
    if code or re.search(r'SCRIPT ERROR|ERROR:|FAIL:|were leaked|still in use', text, re.I):
        raise RuntimeError(f'{name} verification failed (process exit {code}); retained {log_path}\n{text[-5000:]}')


def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Set GODOT_BIN to a Godot 4.7+ executable.')
    destination = OUT / 'relocated' / uuid.uuid4().hex
    results = []
    for mode in ('2d', '3d'):
        target = destination / mode
        target.mkdir(parents=True)
        package = OUT / f'palette_portable_{mode}.zip'
        package_hash = hashlib.sha256(package.read_bytes()).hexdigest()
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert not any('baseline/' in name or 'relocated/' in name or 'collection_tools.gd' in name or 'asset_collection_store.gd' in name for name in names)
            manifest = json.loads(archive.read('export-manifest.json'))
            for name in names:
                if not (target / name).resolve().is_relative_to(target.resolve()):
                    raise ValueError('Unsafe package entry')
            archive.extractall(target)
            for entry in manifest['files']:
                assert hashlib.sha256((target / entry['path']).read_bytes()).hexdigest() == entry['sha256'], entry['path']
        assert not (target / '.godot').exists()
        shutil.copyfile(ROOT / 'tools/test_collection_export_runtime.gd', target / 'verify_palette.gd')
        shutil.copyfile(OUT / f'portable_palette_expectation_{mode}.json', target / 'palette_expectation.json')
        original_settings = settings((target / 'project.godot').read_bytes())
        import_args = ([] if '--visible-import' in sys.argv else ['--headless']) + ['--editor', '--import', '--lsp-port', port(), '--dap-port', port()]
        if '--import-accessibility-dummy' in sys.argv:
            import_args += ['--accessibility-driver', 'dummy']
        stages = [('import', import_args, 180),
                  ('runtime', ['--headless', '--fixed-fps', '60', '--script', 'res://verify_palette.gd'], 120),
                  ('main', ['--headless', '--quit-after', '10'], 60)]
        if '--capture' in sys.argv:
            stages.append(('graphical', ['--fixed-fps', '60', '--script', 'res://verify_palette.gd', '--', '--capture'], 120))
        for name, args, timeout in stages:
            stage([godot, '--path', str(target), '--log-file', str(target / f'engine_{name}.log'), *args], target, name, timeout)
            if name == 'import':
                for path in names:
                    if Path(path).suffix.lower() not in ('.glb', '.gltf', '.png', '.svg', '.webp', '.jpg', '.jpeg', '.ttf', '.otf', '.wav', '.ogg'):
                        continue
                    remap = (target / (path + '.import')).read_text(encoding='utf-8')
                    dependencies = set(re.findall(r'"res://(\.godot/imported/[^"\n]+)"', remap))
                    assert dependencies, path
                    for dependency in dependencies:
                        assert (target / dependency).is_file() and (target / dependency).stat().st_size > 0, dependency
            assert settings((target / 'project.godot').read_bytes()) == original_settings
            assert hashlib.sha256(package.read_bytes()).hexdigest() == package_hash
            results.append({'mode': mode, 'stage': name, 'log': str(target / f'verification_{name}.log')})
            print('PASS: U15 relocated', mode, name, flush=True)
    result = {'destination': str(destination), 'stages': results,
              'import_surface': 'graphical editor' if '--visible-import' in sys.argv else 'headless editor',
              'import_accessibility_driver': 'dummy' if '--import-accessibility-dummy' in sys.argv else 'default'}
    (OUT / 'portable_projects.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('Retained independent projects:', destination)


if __name__ == '__main__':
    main()
