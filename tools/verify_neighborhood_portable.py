"""Verify generated neighborhoods after fresh portable relocation."""
from pathlib import Path
import os
import shutil
import socket
import json
import hashlib
import sys
import uuid
import zipfile
from verify_collection_portable import stage as verify_stage
from verify_companion_portable import settings

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return str(connection.getsockname()[1])


def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot is required')
    logs = ROOT / 'output/verification/asset_expansion/I16'
    themed = '--themes' in sys.argv
    variant = '_themes' if themed else ''
    destination = logs / 'relocated' / uuid.uuid4().hex
    evidence = []
    logs.mkdir(parents=True, exist_ok=True)
    for mode in ('2d', '3d'):
        target = destination / mode
        target.mkdir(parents=True)
        package = ROOT / 'output' / f'neighborhood{variant}_{mode}.zip'
        original_hash = hashlib.sha256(package.read_bytes()).hexdigest()
        with zipfile.ZipFile(package) as archive:
            for name in archive.namelist():
                if not (target / name).resolve().is_relative_to(target.resolve()):
                    raise RuntimeError(f'Unsafe archive entry: {name}')
            archive.extractall(target)
        if (target / '.godot').exists():
            raise RuntimeError('Neighborhood package contains an import cache')
        verifier = 'test_neighborhood_theme_export_runtime.gd' if themed else 'test_neighborhood_export_runtime.gd'
        shutil.copyfile(ROOT / 'tools' / verifier, target / 'verify_neighborhood.gd')
        if themed: shutil.copyfile(logs / f'theme_export_expectation_{mode}.json', target / 'theme_expectation.json')
        original_settings = settings((target / 'project.godot').read_bytes())
        import_args = ([] if '--visible-import' in sys.argv else ['--headless']) + ['--editor', '--import', '--lsp-port', port(), '--dap-port', port()]
        if '--import-accessibility-dummy' in sys.argv: import_args += ['--accessibility-driver', 'dummy']
        stages = [
            ('import', import_args),
            ('runtime', ['--headless', '--fixed-fps', '60', '--script', 'res://verify_neighborhood.gd']),
            ('main', ['--headless', '--quit-after', '10']),
        ]
        if themed and '--capture' in sys.argv:
            stages.append(('graphical', ['--fixed-fps', '60', '--script', 'res://verify_neighborhood.gd', '--', '--capture']))
        for stage, arguments in stages:
            verify_stage([godot, '--path', str(target), '--log-file', str(target / f'engine_{stage}.log'), *arguments], target, stage, 180)
            assert settings((target / 'project.godot').read_bytes()) == original_settings
            assert hashlib.sha256(package.read_bytes()).hexdigest() == original_hash
            evidence.append({'mode':mode,'stage':stage,'log':str(target / f'verification_{stage}.log')})
            print(f'PASS: neighborhood_portable_{mode}_{stage}', flush=True)
    print(f'Neighborhood projects retained for inspection: {destination}')
    name = 'portable_projects_themes.json' if themed else 'portable_projects_legacy.json'
    (logs / name).write_text(json.dumps({'destination':str(destination),'stages':evidence},indent=2)+'\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
