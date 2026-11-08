"""Prepare added sprite packs without changing their source images or the base catalog."""
from pathlib import Path
from collections import defaultdict, Counter
import hashlib
import io
import json
import re
import numpy as np
from scipy import ndimage
from PIL import Image, ImageSequence

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
EXISTING = {'pixel_isometric', 'isometric_rpg_world', 'hanx_lowpoly', 'tinyworks_fire_station', 'imported_prepared', 'reviewed_prepared',
            'audio', 'custom_assets', 'editor', 'supplemental_source', 'supplemental_models', 'supplemental_prepared'}
OUT = ASSETS / 'imported_prepared'
SCENES = ROOT / 'scenes/items/Imported'
items, aliases, skipped = {}, {}, []
signatures = {}
stats = Counter()
DIRS = ['SE', 'E', 'NE', 'N', 'NW', 'W', 'SW', 'S']


def write_image(image, path):
    if path.exists():
        with Image.open(path) as previous:
            if previous.size == image.size and previous.convert('RGBA').tobytes() == image.tobytes(): return
    buffer = io.BytesIO()
    image.save(buffer, format='PNG', optimize=True)
    data = buffer.getvalue()
    if not path.exists() or path.read_bytes() != data:
        temporary = path.with_suffix('.tmp')
        temporary.write_bytes(data)
        temporary.replace(path)


def write_text(text, path):
    if not path.exists() or path.read_text(encoding='utf-8') != text:
        temporary = path.with_suffix('.tmp')
        temporary.write_text(text, encoding='utf-8')
        temporary.replace(path)


def slug(value):
    return re.sub(r'[^a-zA-Z0-9]+', '_', value).strip('_')[:75] or 'asset'


def res(path):
    return 'res://' + path.relative_to(ROOT).as_posix()


def display_name(name):
    parts = name.replace('\\', '/').split('/')
    tail = re.sub(r'_[0-9a-fA-F]{6,12}$', '', parts[-1])
    if re.match(r'^(part_|r\d|idle$|move$|tile$|open)', tail, re.I): tail = ' '.join(parts[-3:])
    elif re.fullmatch(r'[\d. -]+', tail): tail = ' '.join(parts[-2:])
    return re.sub(r'[_/\\]+', ' ', tail).strip().capitalize()


def read(path):
    return Image.open(path).convert('RGBA')


def crop_frames(frames, maximum=512):
    box = None
    for frame in frames:
        current = frame.getchannel('A').getbbox()
        if current:
            box = current if box is None else (min(box[0], current[0]), min(box[1], current[1]), max(box[2], current[2]), max(box[3], current[3]))
    if box is None:
        return []
    factor = min(1.0, maximum / max(box[2] - box[0], box[3] - box[1]), 8192 / (len(frames) * (box[2] - box[0])))
    size = (max(1, round((box[2] - box[0]) * factor)), max(1, round((box[3] - box[1]) * factor)))
    return [frame.crop(box).resize(size, Image.Resampling.NEAREST) for frame in frames]


def classify(pack, name):
    name = name.replace('\\', '/')
    if pack == 'CATS ISOMETRIC ASSET PACK': return 'Blocks'
    text = (pack + '/' + name).lower()
    if any(v in text for v in ['background', 'backdrop', 'example', 'rockspng', 'zrzut', 'overview']): return 'Backdrops'
    if any(v in text for v in ['vehicle', 'cars/', 'car_', 'sedan', 'ambulance', 'boat', 'ship', 'aircraft', 'train', 'hauler', 'truck', 'battlefield']): return 'Vehicles'
    if pack == 'people': return 'People'
    if any(v in text for v in ['tree', 'shrub', 'flora', 'bush', 'rock', 'glacier', 'plant']): return 'Nature'
    if any(v in text for v in ['house', 'building', 'dwelling', 'temple', 'bakery', 'station', 'homestead', 'market', 'architecture', 'hotel', 'factory', 'bank', 'shop']): return 'Buildings'
    if any(v in name.lower() for v in ['terrain', 'ground', 'floor', 'grass', 'dirt', 'path', 'blocks', 'tiles_', '/tile']) or pack in ['CATS ISOMETRIC ASSET PACK', 'isometricStrategy', 'water tileset by Rodwan', 'rodwan_tileset2']: return 'Ground'
    return 'Props'


def register(pack, name, views, sources, tags=None):
    category_kind = classify(pack, name)
    maximum = 1024 if category_kind == 'Backdrops' else 512
    prepared = {key: crop_frames(frames, maximum) for key, frames in views.items()}
    prepared = {key: frames for key, frames in prepared.items() if frames}
    if not prepared:
        skipped.append({'sources': sources, 'reason': 'empty transparent image'})
        return
    signature = hashlib.sha256()
    for key, frames in prepared.items():
        signature.update(key.encode())
        for frame in frames:
            signature.update(str(frame.size).encode())
            signature.update(frame.tobytes())
    signature = signature.hexdigest()
    source_key = pack + '/' + name
    if signature in signatures:
        aliases[source_key] = signatures[signature]
        stats['duplicates'] += 1
        return
    ident = 'Added_' + slug(pack)[:30] + '_' + slug(name)[:50] + '_' + hashlib.sha1(source_key.encode()).hexdigest()[:8]
    if ident in items: raise ValueError('Duplicate source identity: ' + source_key)
    signatures[signature] = ident
    folder = OUT / slug(pack)
    folder.mkdir(parents=True, exist_ok=True)
    directions = {}
    for direction, frames in prepared.items():
        width, height = frames[0].size
        strip = Image.new('RGBA', (width * len(frames), height))
        for index, frame in enumerate(frames): strip.alpha_composite(frame, (index * width, 0))
        filename = folder / (ident + '_' + direction + '.png')
        write_image(strip, filename)
        # A grounded origin keeps the art and its estimated footprint together.
        foot = max(1, min(20, round(width / 32)))
        footprint = [foot, foot]
        if category_kind in ['Vehicles', 'People', 'Props']: footprint = [max(1, min(8, round(width / 48))), 1]
        origin = [round(width / 2 - 16 * (footprint[0] - footprint[1])), max(0, height - 8 * sum(footprint))]
        directions[direction] = {'file': '../../' + filename.relative_to(ASSETS).as_posix(), 'frame_width': width, 'frame_height': height, 'frames': len(frames), 'origin': origin, 'footprint': footprint}
    preferred = 'SE' if 'SE' in directions else next(iter(directions))
    info = directions[preferred]
    category = 'Added ' + re.sub(r' v\d.*$', '', pack) + ' - ' + category_kind
    scene = SCENES / slug(pack) / (ident + '.tscn')
    scene.parent.mkdir(parents=True, exist_ok=True)
    display = display_name(name)
    item = {'name': ident, 'display_name': display, 'category': category, 'kind': 'obj', 'frames': info['frames'], 'fps': 8.0,
            'directions': directions, 'scene_path': res(scene), 'source_pack': pack, 'source_name': name, 'source_files': sources, 'import_tags': tags or [], 'content_hash': signature}
    items[ident] = item
    texture = 'res://assets/' + info['file'].removeprefix('../../')
    collision = category_kind not in ['Backdrops', 'Ground']
    body = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/iso_object.gd" id="1"]
[ext_resource type="Texture2D" path={json.dumps(texture)} id="2"]

[node name={json.dumps(ident)} type="Node2D"]
y_sort_enabled = true
script = ExtResource("1")
item_id = {json.dumps(ident)}
category = {json.dumps(category)}
kind = "obj"
direction = {json.dumps(preferred)}
footprint = Vector2i({info['footprint'][0]}, {info['footprint'][1]})
origin_offset = Vector2({info['origin'][0]}, {info['origin'][1]})
total_frames = {info['frames']}
animation_fps = 8.0
has_collision = {'true' if collision else 'false'}
directions_data = {json.dumps(directions)}

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2")
centered = false
offset = Vector2({-info['origin'][0]}, {-info['origin'][1]})
hframes = {info['frames']}
'''
    write_text(body, scene)
    stats['assets'] += 1
    stats['directional'] += len(directions) > 1
    stats['animated'] += any(view['frames'] > 1 for view in directions.values())
    stats['prepared_views'] += len(directions)


def components(image):
    alpha = np.asarray(image.getchannel('A')) > 20
    labels, count = ndimage.label(ndimage.binary_dilation(alpha, iterations=2))
    boxes = []
    for number, bounds in enumerate(ndimage.find_objects(labels), 1):
        if bounds is None: continue
        y, x = bounds
        if np.count_nonzero(alpha[y, x]) < 8: continue
        boxes.append((max(0, x.start - 1), max(0, y.start - 1), min(image.width, x.stop + 1), min(image.height, y.stop + 1)))
    return sorted(boxes, key=lambda box: (box[1] // 12, box[0]))


def grid(image, width, height):
    for y in range(0, image.height - height + 1, height):
        for x in range(0, image.width - width + 1, width):
            piece = image.crop((x, y, x + width, y + height))
            if piece.getchannel('A').getbbox(): yield f'r{y // height + 1:02}_c{x // width + 1:02}', piece


def car_strip(image):
    alpha = np.asarray(image.getchannel('A')) > 20
    occupied = np.any(alpha, axis=0)
    runs, start = [], None
    for x, value in enumerate(list(occupied) + [False]):
        if value and start is None: start = x
        if not value and start is not None:
            if x - start > 12: runs.append((start, x))
            start = None
    count = len(runs)
    if count in (2, 3, 4, 5, 6, 8) and image.width % count == 0:
        width = image.width // count
        if all(a >= i * width and b <= (i + 1) * width for i, (a, b) in enumerate(runs)):
            return [image.crop((i * width, 0, (i + 1) * width, image.height)) for i in range(count)]
    return [image]


def process_pack(root):
    pack = root.name
    # Referenced runtime images are prepared below; original source/tool files stay unmodified.
    if not (root / '.gdignore').exists(): (root / '.gdignore').write_text('', encoding='utf-8')
    files = sorted([p for p in root.rglob('*') if p.suffix.lower() in ('.png', '.gif')])
    used = set()
    if pack in ['rendered', 'rendered_test', 'people', 'piers']:
        groups = defaultdict(list)
        for path in files:
            match = re.match(r'(.+)_([0-9]{2})$', path.stem)
            if match: groups[(path.parent, match[1])].append((int(match[2]), path))
        for (parent, prefix), entries in groups.items():
            entries.sort()
            views = {DIRS[i] if len(entries) == 8 else f'View_{i + 1:02}': [read(path)] for i, (_, path) in enumerate(entries)}
            name = str(parent.relative_to(root) / prefix)
            register(pack, name, views, [res(path) for _, path in entries], ['directional views'])
            used.update(path for _, path in entries)
    if pack == 'animated':
        for folder in sorted(p for p in root.iterdir() if p.is_dir()):
            frames = sorted(folder.glob('frame_*.png'))
            if frames:
                register(pack, folder.name, {'SE': [read(p) for p in frames]}, [res(p) for p in frames], ['animation'])
                used.update(frames)
    if pack == 'cars':
        groups = defaultdict(dict)
        for path in files:
            match = re.match(r'^(NE|NW|SE|SW|N|E|S|W)[-_]', path.name, re.I)
            if match: groups[path.parent][match[1].upper()] = path
        for folder, paths in groups.items():
            views = {key: car_strip(read(path)) for key, path in paths.items()}
            register(pack, str(folder.relative_to(root)), views, [res(p) for p in paths.values()], ['8-way vehicle animation'])
            used.update(paths.values())
    if pack == 'Isometric tileset':
        groups = defaultdict(dict)
        for path in files:
            match = re.match(r'(.+)_(ne|nw|se|sw|n|e|s|w)([0-9]*)$', path.stem, re.I)
            if match: groups[(path.parent, match[1] + match[3])][match[2].upper()] = path
        for (folder, name), paths in groups.items():
            register(pack, str(folder.relative_to(root) / name), {k: [read(v)] for k, v in paths.items()}, [res(p) for p in paths.values()], ['directional views'])
            used.update(paths.values())
    for path in files:
        if path in used: continue
        relative = path.relative_to(root).as_posix()
        text = relative.lower()
        if any(word in text for word in ['zrzut', 'preview', 'readme', 'licence']) or (pack == 'Isometric RPG Tileset 64x32 Pixel Art V1.1' and path.name.lower().startswith('tileset')):
            skipped.append({'source': res(path), 'reason': 'preview or combined atlas with separate supplied assets'})
            continue
        if path.suffix.lower() == '.gif':
            source = Image.open(path)
            register(pack, str(Path(relative).with_suffix('')), {'SE': [frame.convert('RGBA').copy() for frame in ImageSequence.Iterator(source)]}, [res(path)], ['animation'])
            continue
        image = read(path)
        special_grid = None
        if pack == 'CATS ISOMETRIC ASSET PACK': special_grid = (32, 24 if path.stem == 'half_blocks' else 32)
        elif pack == 'isometricStrategy': special_grid = (64, 64)
        elif pack == 'rodwan_tileset2': special_grid = (32, 16)
        elif pack == 'water tileset by Rodwan': special_grid = (32, 16)
        elif pack == 'Rodwan_Cliffs' and path.name == 'Tileset_Cliffs2.png': special_grid = (32, 32)
        if special_grid:
            for cell, piece in grid(image, *special_grid): register(pack, path.stem + '/' + cell, {'SE': [piece]}, [res(path)], ['sliced tile'])
            continue
        if path.name == 'campfire-Sheet.png':
            register(pack, path.stem, {'SE': [image.crop((x, 0, x + 36, 48)) for x in range(0, image.width, 36)]}, [res(path)], ['animation'])
            continue
        if path.name in ['flag_4-Sheet.png', 'wind_mill_animatiion-Sheet.png']:
            width = 128 if image.height == 200 else image.height
            if image.width % width == 0:
                register(pack, path.stem, {'SE': [image.crop((x, 0, x + width, image.height)) for x in range(0, image.width, width)]}, [res(path)], ['animation'])
                continue
        sheet = ('sheet' in text or 'allthings' in text or pack in ['loose', 'Rodwan_Trees']) and 'hercules' not in text
        if sheet:
            boxes = components(image)
            if len(boxes) > 1:
                for index, box in enumerate(boxes): register(pack, str(Path(relative).with_suffix('')) + f'/part_{index + 1:03}', {'SE': [image.crop(box)]}, [res(path)], ['sliced sheet part'])
                continue
        register(pack, str(Path(relative).with_suffix('')), {'SE': [image]}, [res(path)])


def finalize(registry):
    previews = ROOT / 'resources/previews_imported'
    previews.mkdir(exist_ok=True)
    for ident, item in registry['items'].items():
        # Keep palette browsing light: thumbnails never load an entire animation strip.
        view = item['directions'].get('SE', next(iter(item['directions'].values())))
        path = ASSETS / view['file'].removeprefix('../../')
        image = read(path).crop((0, 0, view['frame_width'], view['frame_height']))
        image.thumbnail((128, 128), Image.Resampling.NEAREST)
        preview = previews / (ident + '.png')
        write_image(image, preview)
        item['preview_path'] = res(preview)
        kind = classify(item['source_pack'], item.get('source_name', item['display_name']))
        item['display_name'] = display_name(item.get('source_name', item['display_name']))
        if 'sliced tile' in item['import_tags'] and item['source_pack'] != 'CATS ISOMETRIC ASSET PACK': kind = 'Ground'
        category = 'Added ' + re.sub(r' v\d.*$', '', item['source_pack']) + ' - ' + kind
        item['category'] = category
        longest = max(view['frame_width'], view['frame_height'])
        item['default_scale'] = 1.0 if kind == 'Backdrops' or longest <= 128 else (0.5 if longest <= 256 else 0.25)
        item.pop('surface', None)
        item.pop('ground_shape', None)
        if kind == 'Ground' and (view['frame_width'] / view['frame_height'] >= 1.5 or image.getchannel('A').getextrema()[0] == 255):
            item['surface'] = 'ground'
            item['ground_shape'] = 'diamond' if 1.5 <= view['frame_width'] / view['frame_height'] <= 2.5 else 'square'
        scene = ROOT / item['scene_path'].removeprefix('res://')
        text = scene.read_text(encoding='utf-8')
        text = re.sub(r'^category = .+$', 'category = ' + json.dumps(category), text, flags=re.M)
        scale = f"scale = Vector2({item['default_scale']}, {item['default_scale']})"
        if re.search(r'^scale = ', text, flags=re.M): text = re.sub(r'^scale = .+$', scale, text, flags=re.M)
        else: text = text.replace('y_sort_enabled = true\n', 'y_sort_enabled = true\n' + scale + '\n', 1)
        text = re.sub(r'^has_collision = .+$', 'has_collision = ' + ('false' if kind in ['Backdrops', 'Ground'] else 'true'), text, flags=re.M)
        write_text(text, scene)


def archive_stale_scenes(registry):
    archive = ROOT / 'output/import_archive'
    for scene in SCENES.rglob('Added_*.tscn'):
        if scene.stem in registry['items']: continue
        destination = archive / scene.relative_to(SCENES)
        destination.parent.mkdir(parents=True, exist_ok=True)
        scene.replace(destination)
        uid = scene.with_suffix('.tscn.uid')
        if uid.exists(): uid.replace(destination.with_suffix('.tscn.uid'))
    if archive.exists(): (archive / '.gdignore').write_text('', encoding='utf-8')


def source_packs(root=ASSETS):
    return [p for p in sorted(root.iterdir()) if p.is_dir() and p.name not in EXISTING]


def main():
    OUT.mkdir(exist_ok=True)
    packs = source_packs()
    for pack in packs:
        before = stats['assets']
        process_pack(pack)
        print(f'{pack.name}: {stats["assets"] - before} prepared assets', flush=True)
    registry = {'version': 1, 'items': items, 'aliases': aliases, 'skipped': skipped, 'stats': dict(stats), 'source_packs': [p.name for p in packs]}
    finalize(registry)
    from calibrate_import_alignment import calibrate
    calibrate(registry)
    archive_stale_scenes(registry)
    target = ROOT / 'resources/catalog/imported_registry.json'
    write_text(json.dumps(registry, ensure_ascii=False, indent=2), target)
    from audit_asset_alignment import audit
    audit(apply=True)
    from prepare_reviewed_sprites import prepare
    prepare()
    from compile_asset_metadata import compile_metadata
    compile_metadata()
    print(json.dumps(dict(stats)), flush=True)


if __name__ == '__main__': main()
