"""Build explicitly reviewed sprite crops without rewriting any legacy asset.

The manifest contains source hashes, rectangles, frame/view grouping and contact
points. No connected-component inference is used to decide what an object is.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import math
import os
import re
import tempfile
import numpy as np
from PIL import Image, ImageSequence
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = 'resources/catalog/reviewed_sprites.json'
REGISTRY = 'resources/catalog/reviewed_registry.json'
KINDS = {'object', 'atlas', 'reference', 'background', 'showcase'}


def source_path(root, value):
    if not isinstance(value, str) or not value.startswith('res://assets/'):
        raise ValueError(f'Expected an asset resource: {value}')
    result = (root / value[6:]).resolve()
    if not result.is_relative_to((root / 'assets').resolve()): raise ValueError('Source escapes assets')
    return result


def identity(key):
    if not key or len(key) > 100 or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789_' for c in key):
        raise ValueError(f'Invalid stable reviewed key: {key}')
    return 'Reviewed_' + key


def numbers(value, length):
    return isinstance(value, list) and len(value) == length and all(type(n) in (int, float) and math.isfinite(n) and abs(n) <= 100000 for n in value)


def clear_border_color(image, rgb):
    """Only remove the explicitly approved color connected to the border."""
    data = np.array(image.convert('RGBA'))
    mask = np.all(data[:, :, :3] == rgb, axis=2)
    seeds = np.zeros(mask.shape, dtype=bool)
    seeds[0, :] = mask[0, :]; seeds[-1, :] = mask[-1, :]
    seeds[:, 0] |= mask[:, 0]; seeds[:, -1] |= mask[:, -1]
    background = ndimage.binary_propagation(seeds, mask=mask)
    data[background, 3] = 0
    return Image.fromarray(data)


def load_frames(path, rgb=None):
    with Image.open(path) as image:
        frames = [frame.convert('RGBA').copy() for frame in ImageSequence.Iterator(image)]
    return [clear_border_color(frame, rgb) for frame in frames] if rgb is not None else frames


def encode(image):
    buffer = io.BytesIO(); image.save(buffer, format='PNG', optimize=True)
    return buffer.getvalue()


def install(root, outputs, check):
    """Validate staged bytes before replacing files; publish the registry last."""
    stale = [name for name, content in outputs.items() if not (root / name).is_file() or (root / name).read_bytes() != content]
    if check:
        if stale: raise ValueError('Reviewed sprites are stale: ' + ', '.join(stale[:5]))
        return
    if not stale: return
    report = root / 'output/verification/asset_expansion/I03'; report.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='prepare-', dir=report) as temporary:
        staged = Path(temporary)
        for index, name in enumerate(stale):
            path = staged / str(index); path.write_bytes(outputs[name])
            if name.endswith('.png'):
                with Image.open(path) as image: image.verify()
            elif name.endswith('.json'): json.loads(path.read_text(encoding='utf-8'))
        for index, name in enumerate(stale):
            target = root / name; target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staged / str(index), target)


def prepare(root=ROOT, check=False):
    manifest = json.loads((root / MANIFEST).read_text(encoding='utf-8'))
    if manifest.get('version') != 1: raise ValueError('Unsupported reviewed-sprite manifest')
    legacy = {}
    for filename in ('catalog_registry.json', 'imported_registry.json'):
        path = root / 'resources/catalog' / filename
        if path.is_file(): legacy.update(json.loads(path.read_text(encoding='utf-8')).get('items', {}))
    reviewed = manifest['reviews']; definitions = manifest['assets']
    # Validate every approved input before generating or replacing output.
    for ident, review in reviewed.items():
        if ident[3:] not in legacy or not ident.startswith('2d:') or review.get('content_kind') not in KINDS:
            raise ValueError('Unknown asset or content classification: ' + ident)
        for location, expected in review['source_sha256'].items():
            actual = hashlib.sha256(source_path(root, location).read_bytes()).hexdigest()
            if actual != expected: raise ValueError('Source changed; review its crops again: ' + location)
    output = {}; items = {}; cache = {}
    for key, definition in sorted(definitions.items()):
        ident = identity(key); source_id = definition['source_asset']
        if source_id not in reviewed: raise ValueError('Unreviewed source asset: ' + source_id)
        if definition.get('content_kind', 'object') not in KINDS: raise ValueError('Invalid content kind: ' + key)
        for field in ('display_name', 'category'):
            if not isinstance(definition.get(field), str) or not 1 <= len(definition[field]) <= 128: raise ValueError('Invalid label: ' + key)
        scale = definition.get('scale', 1.0)
        if type(scale) not in (int, float) or not math.isfinite(scale) or not .01 <= scale <= 100: raise ValueError('Invalid scale: ' + key)
        collidable = definition.get('collision', definition.get('content_kind', 'object') == 'object' and not definition.get('ground', False))
        if not isinstance(collidable, bool): raise ValueError('Invalid collision policy: ' + key)
        old = legacy[source_id[3:]]; views = {}
        rgb = definition.get('border_color')
        if rgb is not None and (not numbers(rgb, 3) or any(type(n) is not int or n < 0 or n > 255 for n in rgb)):
            raise ValueError('Invalid approved border color')
        for direction, view in definition['views'].items():
            if not re.fullmatch(r'[A-Za-z0-9_]{1,32}', direction): raise ValueError('Invalid view name: ' + key)
            path = view['source']
            if path not in reviewed[source_id]['source_sha256']: raise ValueError('View uses an unreviewed source: ' + path)
            cache_key = (path, tuple(rgb) if rgb is not None else None)
            if cache_key not in cache: cache[cache_key] = load_frames(source_path(root, path), rgb)
            originals = cache[cache_key]; frames = []
            for frame in view['frames']:
                rect = frame['rect']; index = frame.get('source_frame', 0)
                if not numbers(rect, 4) or any(type(n) is not int for n in rect) or min(rect[:2]) < 0 or min(rect[2:]) < 1:
                    raise ValueError('Invalid crop rectangle: ' + key)
                if type(index) is not int or not 0 <= index < len(originals): raise ValueError('Invalid source frame: ' + key)
                source = originals[index]; x, y, width, height = rect
                if x + width > source.width or y + height > source.height: raise ValueError('Crop exceeds source: ' + key)
                crop = source.crop((x, y, x + width, y + height))
                if not crop.getchannel('A').getbbox(): raise ValueError('Crop is empty: ' + key)
                if frames and crop.size != frames[0].size: raise ValueError('Unequal frame canvases: ' + key)
                frames.append(crop)
            if not frames or len(frames) > 256: raise ValueError('Invalid frame group: ' + key)
            width, height = frames[0].size
            if width * len(frames) > 8192 or max(width, height) > 2048: raise ValueError('Prepared strip exceeds bounds: ' + key)
            contact = view['contact']; footprint = view['footprint']
            if not numbers(contact, 2) or not 0 <= contact[0] <= width or not 0 <= contact[1] <= height:
                raise ValueError('Invalid ground contact: ' + key)
            if not numbers(footprint, 2) or any(type(n) is not int or not 1 <= n <= 32 for n in footprint):
                raise ValueError('Invalid reviewed footprint: ' + key)
            origin = [contact[0], contact[1] - 8 * sum(footprint)]
            filename = f'assets/reviewed_prepared/{ident}_{direction}.png'
            strip = Image.new('RGBA', (width * len(frames), height))
            for index, frame in enumerate(frames): strip.paste(frame, (index * width, 0))
            output[filename] = encode(strip)
            views[direction] = {'file': '../../' + filename.removeprefix('assets/'), 'frame_width': width, 'frame_height': height,
                                'frames': len(frames), 'origin': origin, 'footprint': footprint, 'source_contact': contact,
                                'grid_contact': contact, 'render_contact': contact,
                                'grid_method': 'reviewed source contact and virtual footprint'}
        if not views: raise ValueError('No supplied views: ' + key)
        preferred = 'SE' if 'SE' in views else next(iter(views)); view = views[preferred]
        fps = definition.get('fps', 8)
        if type(fps) not in (int, float) or not math.isfinite(fps) or not .1 <= fps <= 120: raise ValueError('Invalid playback rate: ' + key)
        scene = f'scenes/items/Reviewed/{ident}.tscn'
        item = {'name': ident, 'display_name': definition['display_name'], 'category': definition['category'], 'kind': 'obj',
                'fps': fps, 'frames': view['frames'], 'directions': views, 'scene_path': 'res://' + scene,
                'source_pack': old['source_pack'], 'source_name': old['source_name'] + ' / ' + definition['display_name'],
                'source_files': sorted({v['source'] for v in definition['views'].values()}), 'source_asset': source_id,
                'source_export_allowed': old.get('source_export_allowed', True), 'default_scale': definition.get('scale', 1.0),
                'content_kind': definition.get('content_kind', 'object'), 'reviewed_key': key,
                'behavior': {'layer': definition.get('layer', 'Decorations'), 'building': False, 'entrance': False, 'door': False,
                             'ground': definition.get('ground', False), 'vehicle': False,
                             'collision': 'box' if collidable else 'none'}}
        if definition.get('content_note'): item['content_note'] = definition['content_note']
        if definition.get('ground'): item.update(surface='ground', ground_shape='diamond')
        if definition.get('source_view_kind') == 'state': item['source_view_kind'] = 'state'
        preview_path = f'resources/previews_reviewed/{ident}.png'
        preview = Image.open(io.BytesIO(output['assets/' + view['file'][6:]])).crop((0, 0, view['frame_width'], view['frame_height']))
        preview.thumbnail((128,128),Image.Resampling.NEAREST); output[preview_path] = encode(preview)
        item['preview_path'] = 'res://' + preview_path
        texture = 'res://assets/' + view['file'][6:]
        output[scene] = (f'''[gd_scene load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/iso_object.gd" id="1"]
[ext_resource type="Texture2D" path={json.dumps(texture)} id="2"]
[node name={json.dumps(ident)} type="Node2D"]
y_sort_enabled = true
script = ExtResource("1")
item_id = {json.dumps(ident)}
category = {json.dumps(item['category'])}
kind = "obj"
direction = {json.dumps(preferred)}
footprint = Vector2i({view['footprint'][0]}, {view['footprint'][1]})
origin_offset = Vector2({view['origin'][0]}, {view['origin'][1]})
scale = Vector2({item['default_scale']}, {item['default_scale']})
total_frames = {view['frames']}
animation_fps = {fps}
has_collision = {'true' if collidable else 'false'}
directions_data = {json.dumps(views)}
[node name="Sprite2D" type="Sprite2D" parent="."]
texture = ExtResource("2")
centered = false
offset = Vector2({-view['origin'][0]}, {-view['origin'][1]})
hframes = {view['frames']}
''').encode()
        items[ident] = item
    replacements = {}
    for ident, values in manifest.get('replacements', {}).items():
        if ident not in reviewed and ident[3:] not in items: raise ValueError('Unreviewed replacement source')
        replacements[ident] = [value if value.startswith('2d:') else '2d:' + identity(value) for value in values]
        for target in replacements[ident]:
            if target[3:] not in items and target[3:] not in legacy: raise ValueError('Unknown replacement: ' + target)
        if ident[3:] in items: items[ident[3:]]['replacement_ids'] = replacements[ident]
    metadata = {ident: {'content_kind': entry['content_kind'], 'content_note': entry['note'], 'replacement_ids': replacements.get(ident, [])}
                for ident, entry in reviewed.items()}
    registry = {'version': 1, 'items': items, 'legacy_content': metadata}
    previous = root / REGISTRY
    if previous.is_file():
        removed = set(json.loads(previous.read_text(encoding='utf-8')).get('items', {})) - items.keys()
        if removed: raise ValueError('Reviewed IDs must remain recoverable; removing definitions is not allowed: ' + ', '.join(sorted(removed)))
    output[REGISTRY] = (json.dumps(registry, ensure_ascii=False, indent=2) + '\n').encode()
    install(root, output, check)
    print(f'Reviewed sprites: {len(reviewed)} legacy entries preserved, {len(items)} reviewed definitions; {"checked" if check else "prepared"}')
    return registry


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--check', action='store_true')
    prepare(check=parser.parse_args().check)
