"""Verify physical 3D stair traversal in a fresh relocated source package."""
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
    target = ROOT.parent / 'IsoCity-portable-validation' / 'IsoCity-floor-stairs-verification' / uuid.uuid4().hex
    target.mkdir(parents=True)
    logs = ROOT / 'output' / 'verification'
    logs.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(ROOT / 'output' / 'floor_stairs_3d.zip') as archive:
        for name in archive.namelist():
            if not (target / name).resolve().is_relative_to(target):
                raise RuntimeError(f'Unsafe archive entry: {name}')
        archive.extractall(target)
    if (target / '.godot').exists():
        raise RuntimeError('Floor package contains an import cache')
    shutil.copyfile(ROOT / 'tools' / 'test_floor_stairs_export_runtime.gd', target / 'verify_floor_stairs.gd')
    for stage, arguments in (
        ('import', ['--editor', '--import', '--quit', '--lsp-port', port(), '--dap-port', port()]),
        ('runtime', ['--fixed-fps', '60', '--script', 'res://verify_floor_stairs.gd']),
        ('main', ['--quit-after', '10']),
    ):
        result = run_relocated_stage([godot, '--headless', '--path', str(target), *arguments], cwd=target,
                                capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        output = result.stdout + result.stderr
        (logs / f'floor_stairs_portable_3d_{stage}.log').write_text(output, encoding='utf-8')
        if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:)', output):
            print(output)
            raise RuntimeError(f'Floor stairs {stage} verification failed')
        print(f'PASS: floor_stairs_portable_3d_{stage}', flush=True)
    print(f'Floor stairs project retained for inspection: {target}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
