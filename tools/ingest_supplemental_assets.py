"""Reproducible intake of the post-60/60 source packs, preserving original archives."""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'more assets to ingest after its complete'
RAW = ROOT / 'assets' / 'supplemental_source'
REPORT = ROOT / 'output' / 'supplemental_assets'


def slug(value):
    return re.sub(r'[^a-zA-Z0-9_-]+', '_', value).strip('_')


def digest(path):
    with path.open('rb') as stream:
        result = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def destination(folder, name):
    name = name.replace('\\', '/')
    if any(part in ('..', '') or ':' in part for part in name.split('/')) or name.startswith('/'):
        raise ValueError(f'Unsafe archive path: {name!r}')
    result = (folder / name).resolve()
    if not result.is_relative_to(folder.resolve()):
        raise ValueError(f'Archive path escapes destination: {name!r}')
    return result


def extract_zip(path, folder):
    folder.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path) as archive:
        if sum(info.file_size for info in archive.infolist()) > 1024 * 1024 * 1024:
            raise ValueError(f'Archive exceeds 1 GiB expanded intake limit: {path}')
        for info in archive.infolist():
            if info.is_dir() or info.filename.startswith('__MACOSX/') or Path(info.filename).name == '.DS_Store':
                continue
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError(f'Archive symlink refused: {info.filename}')
            target = destination(folder, info.filename)
            data = archive.read(info)
            if target.exists():
                if target.read_bytes() != data:
                    raise ValueError(f'Source parts disagree: {target}')
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)


def extract_rar(path, folder):
    executable = shutil.which('7z')
    if not executable:
        raise RuntimeError('7-Zip is required for the supplied RAR character actions')
    listing = subprocess.run([executable, 'l', '-slt', '-ba', str(path)], capture_output=True,
                             text=True, encoding='utf-8', errors='replace', check=True).stdout
    for record in listing.split('\n\n'):
        values = dict(line.split(' = ', 1) for line in record.splitlines() if ' = ' in line)
        if 'Path' in values:
            destination(folder, values['Path'])
        if values.get('Symbolic Link') or values.get('Hard Link'):
            raise ValueError(f'Archive link refused: {path}')
        if int(values.get('Size', '0')) > 256 * 1024 * 1024:
            raise ValueError(f'Unexpected large character file: {path}')
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run([executable, 'x', '-y', '-aoa', '-bso0', '-bsp0', f'-o{folder}', str(path)], check=True)


def extract_sources():
    RAW.mkdir(parents=True, exist_ok=True)
    (RAW / '.gdignore').write_text('', encoding='utf-8')
    REPORT.mkdir(parents=True, exist_ok=True)
    manifest = []
    for source in sorted(SOURCE.iterdir()):
        if source.name == '.gdignore':
            continue
        if source.is_dir():
            target = RAW / slug(source.name)
            shutil.copytree(source, target, dirs_exist_ok=True)
            files = sorted(p for p in target.rglob('*') if p.is_file())
            manifest.append({'source': source.name, 'destination': target.relative_to(ROOT).as_posix(),
                             'files': len(files), 'archives': []})
        elif source.suffix.lower() == '.zip':
            name = re.sub(r'_part_\d+$', '', source.stem)
            target = RAW / slug(name)
            extract_zip(source, target)
            manifest.append({'source': source.name, 'sha256': digest(source),
                             'destination': target.relative_to(ROOT).as_posix()})
        else:
            continue
        print(f'Prepared source: {source.name}', flush=True)
    # Nested character archives stay separate, including revisions with the same filenames.
    for depth in range(4):
        pending = [p for p in sorted(RAW.rglob('*')) if p.suffix.lower() in ('.zip', '.rar')
                   and not p.with_name(p.name + '.intake.json').exists()]
        if not pending:
            break
        for path in pending:
            folder = path.with_name(slug(path.stem) + '_unpacked')
            (extract_zip if path.suffix.lower() == '.zip' else extract_rar)(path, folder)
            record = {'source': path.relative_to(RAW).as_posix(), 'sha256': digest(path),
                      'destination': folder.relative_to(RAW).as_posix()}
            path.with_name(path.name + '.intake.json').write_text(json.dumps(record, indent=2), encoding='utf-8')
            print(f'Prepared nested source: {record["source"]}', flush=True)
    else:
        raise RuntimeError('Nested archive intake exceeded four levels')
    manifest.extend(json.loads(path.read_text(encoding='utf-8')) for path in sorted(RAW.rglob('*.intake.json')))
    (REPORT / 'source_manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    counts = Counter(path.suffix.lower() for path in RAW.rglob('*') if path.is_file())
    print(f'Intake complete: {dict(counts)}', flush=True)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extract', action='store_true', help='Prepare ignored source copies and nested archives')
    args = parser.parse_args()
    if args.extract:
        extract_sources()
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
