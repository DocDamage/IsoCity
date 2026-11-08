"""Freshly import both challenges in both dimensions away from the checkout."""
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
    destination = ROOT.parent / 'IsoCity-portable-validation' / 'IsoCity-scenario-verification' / uuid.uuid4().hex
    logs = ROOT / 'output' / 'verification'
    logs.mkdir(parents=True, exist_ok=True)
    for kind in ('walkable', 'apartment'):
        for mode in ('2d', '3d'):
            target = destination / kind / mode
            target.mkdir(parents=True)
            with zipfile.ZipFile(ROOT / 'output' / f'scenario_{kind}_{mode}.zip') as archive:
                for name in archive.namelist():
                    if not (target / name).resolve().is_relative_to(target):
                        raise RuntimeError(f'Unsafe archive entry: {name}')
                archive.extractall(target)
            if (target / '.godot').exists():
                raise RuntimeError('Scenario package contains an import cache')
            shutil.copyfile(ROOT / 'tools' / 'test_scenario_export_runtime.gd', target / 'verify_scenario.gd')
            for stage, arguments in (
                ('import', ['--editor', '--import', '--quit', '--lsp-port', port(), '--dap-port', port()]),
                ('runtime', ['--script', 'res://verify_scenario.gd']),
                ('main', ['--quit-after', '10']),
            ):
                result = run_relocated_stage([godot, '--headless', '--path', str(target), *arguments], cwd=target,
                                        capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
                output = result.stdout + result.stderr
                (logs / f'scenario_{kind}_portable_{mode}_{stage}.log').write_text(output, encoding='utf-8')
                if result.returncode or re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:)', output):
                    print(output)
                    raise RuntimeError(f'Scenario {kind} {mode} {stage} verification failed')
                print(f'PASS: scenario_{kind}_portable_{mode}_{stage}', flush=True)
    print(f'Scenario projects retained for inspection: {destination}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
