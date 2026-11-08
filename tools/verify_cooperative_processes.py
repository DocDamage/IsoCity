"""Exercise three separate Studio processes through real authenticated TCP sessions."""
from pathlib import Path
import json
import os
import re
import shutil
import socket
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def main():
    godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
    if not godot:
        raise RuntimeError('Godot is required')
    with socket.socket() as connection:
        connection.bind(('127.0.0.1', 0))
        port = connection.getsockname()[1]
    folder = ROOT / 'output' / 'verification' / ('cooperative-process-' + uuid.uuid4().hex)
    folder.mkdir(parents=True)
    processes = {}
    handles = {}
    sequence = {name: 0 for name in ('host', 'alice', 'bob')}
    checks = 0

    def start(name):
        handles[name] = (folder / (name + '.log')).open('w', encoding='utf-8')
        processes[name] = subprocess.Popen([
            godot, '--headless', '--fixed-fps', '60', '--path', str(ROOT),
            '--script', 'res://tools/test_cooperative_peer.gd', '--', '--test',
            '--role', name, '--port', str(port), '--directory', str(folder),
        ], cwd=ROOT, stdout=handles[name], stderr=subprocess.STDOUT)

    def states():
        result = {}
        for name, process in processes.items():
            if process.poll() is not None:
                raise RuntimeError(f'{name} stopped before the check completed')
            try:
                result[name] = json.loads((folder / (name + '.json')).read_text(encoding='utf-8'))
            except (FileNotFoundError, json.JSONDecodeError, PermissionError):
                return {}
        return result

    def expect(predicate, label, timeout=20):
        nonlocal checks
        deadline = time.monotonic() + timeout
        last = {}
        while time.monotonic() < deadline:
            last = states()
            if last and predicate(last):
                checks += 1
                print('PASS: cooperative_process_' + label, flush=True)
                return last
            time.sleep(.05)
        raise RuntimeError(f'Timed out: {label}; latest statuses: ' + repr({k: (v['notice'], v['revision'], v['pending'], v['dirty']) for k, v in last.items()}))

    def send(name, action, **values):
        sequence[name] += 1
        path = folder / (name + '-command-' + str(sequence[name]) + '.json')
        partial = path.with_suffix('.partial')
        partial.write_text(json.dumps({'sequence': sequence[name], 'action': action, **values}), encoding='utf-8')
        partial.replace(path)

    def settled(values):
        return len(values) == 3 and all(v['connected'] and not v['pending'] and not v['dirty'] for v in values.values()) and len({v['revision'] for v in values.values()}) == 1 and values['host']['data'] == values['alice']['data'] == values['bob']['data']

    try:
        start('host')
        expect(lambda s: s['host']['connected'], 'host_started')
        start('alice')
        start('bob')
        expect(lambda s: settled(s) and len(s['host']['members']) == 3, 'three_editors_joined')
        send('alice', 'place', uid='alice_city', position=[100, 0, 0])
        send('bob', 'place', uid='bob_city', position=[300, 0, 0])
        expect(lambda s: settled(s) and len(s['host']['data']['2d']['objects']) == 2, 'concurrent_building_converged')
        send('host', 'protect', owner='Alice')
        expect(lambda s: settled(s) and len(s['host']['data']['2d']['protected_areas']) == 1, 'area_assignment_shared')
        send('bob', 'place', uid='forbidden', position=[0, 0, 0])
        expect(lambda s: settled(s) and s['bob']['failed_edit'] and all(x['uid'] != 'forbidden' for x in s['host']['data']['2d']['objects']) and any(x['uid'] == 'forbidden' for x in s['bob']['draft']['2d']['objects']), 'protected_edit_refused_and_recoverable')
        send('alice', 'place', uid='permitted', position=[0, 0, 0])
        expect(lambda s: settled(s) and len(s['host']['data']['2d']['objects']) == 3, 'owner_construction_accepted')
        send('alice', 'cursor', mode='2d')
        expect(lambda s: s['host']['cursor_count'] >= 1 and s['bob']['cursor_count'] >= 1, 'visible_cursor_relayed')
        send('alice', 'place', mode='3d', uid='alice_3d', position=[10, 0, 0])
        send('bob', 'place', mode='3d', uid='bob_3d', position=[20, 0, 0])
        expect(lambda s: settled(s) and len(s['host']['data']['3d']['objects']) == 2, 'second_view_converged')
        send('bob', 'undo')
        expect(lambda s: settled(s) and len(s['host']['data']['3d']['objects']) == 1, 'shared_undo')
        send('bob', 'redo')
        expect(lambda s: settled(s) and len(s['host']['data']['3d']['objects']) == 2, 'shared_redo')
        identity = states()['bob']['id']
        send('bob', 'leave')
        expect(lambda s: not s['bob']['connected'] and len(s['host']['members']) == 2, 'disconnect_removed_presence')
        send('bob', 'join')
        expect(lambda s: settled(s) and s['bob']['id'] == identity and len(s['host']['members']) == 3, 'reconnect_preserved_identity')
        for name in processes:
            send(name, 'quit')
        for name, process in processes.items():
            if process.wait(timeout=20):
                raise RuntimeError(f'{name} exited with a failure')
            handles[name].flush()
            log = (folder / (name + '.log')).read_text(encoding='utf-8', errors='replace')
            if re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:)|were leaked at exit', log):
                raise RuntimeError(f'{name} reported errors: {log[:5000]}')
            checks += 1
            print('PASS: cooperative_process_' + name + '_clean_shutdown', flush=True)
        print(f'Cooperative processes: {checks} checks, 0 failures', flush=True)
        print(f'Cooperative process artifacts: {folder}', flush=True)
        return 0
    finally:
        for process in processes.values():
            if process.poll() is None:
                if os.name == 'nt':
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                else:
                    process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
        for handle in handles.values():
            handle.close()


if __name__ == '__main__':
    raise SystemExit(main())
