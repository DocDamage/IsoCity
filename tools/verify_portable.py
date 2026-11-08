"""Verify exported source packages after relocation and a fresh Godot import."""
from pathlib import Path
import argparse
import os
import re
import shutil
import socket
import subprocess
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return str(s.getsockname()[1])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--capture', action='store_true')
    parser.add_argument('--existing', action='store_true', help='Use the already generated test ZIPs')
    args = parser.parse_args()
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot is required')
    logs = ROOT / 'output' / 'verification'
    logs.mkdir(parents=True, exist_ok=True)

    def run(label, project, arguments, headless=True):
        result = subprocess.run([godot, *(['--headless'] if headless else []), '--path', str(project), *arguments],
                                cwd=project, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        output = result.stdout + result.stderr
        (logs / f'{label}.log').write_text(output, encoding='utf-8')
        if result.returncode or re.search(r'(?m)^(?:SCRIPT ERROR:|ERROR:|FAIL:)', output):
            print(output)
            raise RuntimeError(f'{label} failed (exit {result.returncode})')
        print(f'PASS: {label}', flush=True)

    if not args.existing:
        run('portable_export', ROOT, ['--script', 'res://tools/test_portable_export.gd', '--', '--test'])
    relocated = ROOT.parent / 'IsoCity-portable-validation' / 'IsoCity-portable-verification' / uuid.uuid4().hex
    for mode in ('2d', '3d'):
        target = relocated / mode
        target.mkdir(parents=True)
        with zipfile.ZipFile(ROOT / 'output' / 'portable' / f'{mode}.zip') as archive:
            for name in archive.namelist():
                resolved = (target / name).resolve()
                if not resolved.is_relative_to(target.resolve()):
                    raise RuntimeError(f'Unsafe ZIP entry: {name}')
            archive.extractall(target)
        if (target / '.godot').exists():
            raise RuntimeError('Package unexpectedly contains an import cache')
        shutil.copyfile(ROOT / 'tools' / 'test_portable_runtime.gd', target / 'verify_runtime.gd')
        run(f'portable_import_{mode}', target, ['--editor', '--import', '--quit', '--lsp-port', port(), '--dap-port', port()])
        run(f'portable_runtime_{mode}', target, ['--script', 'res://verify_runtime.gd', '--', *(['--capture'] if args.capture else [])], not args.capture)
        # Run the actual configured main scene as well as the integration probe.
        run(f'portable_main_{mode}', target, ['--quit-after', '10'])
        if args.capture:
            shutil.copyfile(target / 'portable_room.png', ROOT / 'output' / f'portable_room_{mode}.png')
    print(f'Relocated projects retained for inspection: {relocated}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
