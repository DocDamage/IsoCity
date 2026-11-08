"""Verify prop interactions, rigs and local state after fresh relocation."""
from pathlib import Path
import os
import re
import shutil
import socket
import uuid
import zipfile

from verify_construction_costs_portable import run_relocated_stage

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        return str(connection.getsockname()[1])


def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot is required')
    destination = ROOT.parent / 'IsoCity-portable-validation' / 'IsoCity-props-verification' / uuid.uuid4().hex
    logs = ROOT / 'output' / 'verification'
    logs.mkdir(parents=True, exist_ok=True)
    for mode in ('2d', '3d'):
        target = destination / mode
        target.mkdir(parents=True)
        with zipfile.ZipFile(ROOT / 'output' / f'props_{mode}.zip') as archive:
            for name in archive.namelist():
                if not (target / name).resolve().is_relative_to(target):
                    raise RuntimeError(f'Unsafe archive entry: {name}')
            required = ['resources/catalog/props.json'] + [
                f'scripts/builder/prop_{part}.gd' for part in ('runtime', 'plan', 'effects', 'swing', 'swing_2d')]
            missing = set(required) - set(archive.namelist())
            if missing:
                raise RuntimeError(f'Missing props dependencies: {sorted(missing)}')
            archive.extractall(target)
        if (target / '.godot').exists():
            raise RuntimeError('Props package contains an import cache')
        shutil.copyfile(ROOT / 'tools' / 'test_props_export_runtime.gd', target / 'verify_props.gd')
        for stage, arguments in (
            ('import', ['--editor', '--import', '--quit', '--lsp-port', port(), '--dap-port', port()]),
            ('runtime', ['--disable-render-loop', '--fixed-fps', '60', '--script', 'res://verify_props.gd']),
            ('main', ['--quit-after', '10']),
        ):
            result = run_relocated_stage([godot, '--headless', '--path', str(target), *arguments], cwd=target,
                                    capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
            output = result.stdout + result.stderr
            (logs / f'props_portable_{mode}_{stage}.log').write_text(output, encoding='utf-8')
            if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)', output):
                print(output)
                raise RuntimeError(f'Props {mode} {stage} verification failed')
            print(f'PASS: props_portable_{mode}_{stage}', flush=True)
    print(f'Props projects retained for inspection: {destination}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
