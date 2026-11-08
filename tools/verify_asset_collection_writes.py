"""Exercise real Windows replacement failures while retaining the good files."""
from pathlib import Path
import ctypes, hashlib, json, os, re, shutil, subprocess
from ctypes import wintypes
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output/verification/asset_expansion/U15'

def main():
    if os.name != 'nt':
        raise RuntimeError('This replacement-denial fixture requires Windows file sharing semantics.')
    target = OUT / 'locked_writes'
    target.mkdir(parents=True, exist_ok=True)
    collection = {'uid': 'locked_collection', 'name': 'Good prior collection', 'entries': [{'kind': 'asset', 'id': '3d:HanX_School/Student_Chair', 'name': 'Student Chair'}]}
    values = {'preferences.json': {'version': 1, 'collections': [collection], 'selected': '', 'favorites_migrated': True}, 'export.json': {'format': 'IsoCity asset collections', 'version': 1, 'collections': [collection]}}
    for name, value in values.items():
        (target / name).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')
    hashes = {name: hashlib.sha256((target / name).read_bytes()).hexdigest() for name in values}
    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel.CreateFileW.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.CloseHandle.restype = wintypes.BOOL
    handles = []
    try:
        for name in values:
            # Allow reads, deny writes and deletion/replacement of this exact file.
            handle = kernel.CreateFileW(str(target / name), 0x80000000, 1, None, 3, 0x80, None)
            if handle == ctypes.c_void_p(-1).value:
                raise ctypes.WinError(ctypes.get_last_error())
            handles.append(handle)
        godot = os.environ.get('GODOT_BIN') or shutil.which('godot_console') or shutil.which('godot')
        if not godot:
            raise RuntimeError('Godot required')
        command = [godot, '--path', str(ROOT), '--headless', '--script', 'res://tools/test_asset_collection_locked_write.gd']
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, encoding='utf-8', errors='replace')
        try:
            stdout, stderr = process.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], cwd=ROOT, capture_output=True, timeout=15)
            stdout, stderr = process.communicate(timeout=15)
            (OUT / 'locked_write_timeout.log').write_text(stdout + stderr, encoding='utf-8')
            raise RuntimeError('Locked-write fixture timed out; its process tree was stopped.')
        log = f'Process exit: {process.returncode}\nCommand: ' + json.dumps(command) + '\n' + stdout + stderr
        (OUT / 'locked_write.log').write_text(log, encoding='utf-8')
        assert process.returncode == 0 and not re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:|WARNING: .*were leaked at exit)', stdout + stderr), log
    finally:
        for handle in handles:
            kernel.CloseHandle(handle)
    for name, digest in hashes.items():
        assert hashlib.sha256((target / name).read_bytes()).hexdigest() == digest, name
    assert not list(target.glob('*.tmp'))
    (OUT / 'locked_write_hashes.json').write_text(json.dumps(hashes, indent=2) + '\n', encoding='utf-8')
    print('PASS: locked preferences and export retain their exact prior bytes after actual replacement denials')

if __name__ == '__main__':
    main()
