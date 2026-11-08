"""Prepare catalog-ready views from the supplemental intake, never treating previews as props."""
from pathlib import Path
from collections import Counter
import hashlib
import json
import math
import re
import sys
import argparse
from PIL import Image
from ingest_supplemental_assets import ROOT, RAW, REPORT, slug

OUT = ROOT / 'assets/supplemental_prepared'
SCENES = ROOT / 'scenes/items/Supplemental'
REGISTRY = ROOT / 'resources/catalog/supplemental_registry.json'


def res(path):
    return 'res://' + path.relative_to(ROOT).as_posix()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    raw = value.encode('utf-8') if isinstance(value, str) else value
    if not path.exists() or path.read_bytes() != raw:
        temporary = path.with_name(path.name + '.partial')
        temporary.write_bytes(raw)
        temporary.replace(path)


def human(value):
    return re.sub(r'[_-]+', ' ', value).strip().capitalize()


class Builder:
    def __init__(self, existing=False):
        self.items, self.aliases, self.signatures = {}, {}, {}
        self.stats = Counter()
        self.notes = []
        self.models = {}
        if existing and REGISTRY.exists():
            raw = json.loads(REGISTRY.read_text(encoding='utf-8'))
            self.items = raw.get('items', {})
            self.aliases = raw.get('aliases', {})
            self.models = raw.get('models', {})
            self.notes = raw.get('notes', [])
            self.stats.update(raw.get('stats', {}))
            for ident,item in self.items.items():
                if item.get('kind')!='char' or item['content_hash'] not in self.signatures: self.signatures[item['content_hash']]=ident

    def sprite(self, pack, key, label, views, *, anchors=None, footprint=(1, 1), scale=1.0,
               category='Props', fps=8.0, sources=(), behavior=None, metadata=None):
        """Keep supplied pivots stable; one atlas per asset, with one strip per authored view."""
        anchors = anchors or {}
        frames = {direction: [frame.convert('RGBA') for frame in sequence]
                  for direction, sequence in views.items() if sequence}
        if not frames:
            raise ValueError(f'Empty asset: {pack}/{key}')
        sizes = {frame.size for sequence in frames.values() for frame in sequence}
        if len(sizes) != 1:
            raise ValueError(f'Inconsistent authored cell sizes: {pack}/{key}: {sizes}')
        width, height = next(iter(sizes))
        longest = max(map(len, frames.values()))
        # Long character clips retain every frame; scale their prepared cells rather than truncate time.
        factor = min(1.0, 8192 / (width * longest), 8192 / height)
        if factor < 1:
            new_size = (max(1, math.floor(width * factor)), max(1, math.floor(height * factor)))
            frames = {direction: [frame.resize(new_size, Image.Resampling.NEAREST) for frame in sequence]
                      for direction, sequence in frames.items()}
            factor = new_size[0] / width
            anchors = {direction: (point[0] * new_size[0] / width, point[1] * new_size[1] / height)
                       for direction, point in anchors.items()}
            width, height = new_size
            scale /= factor
        content = hashlib.sha256()
        for direction, sequence in frames.items():
            content.update(direction.encode())
            for frame in sequence:
                content.update(str(frame.size).encode())
                content.update(frame.tobytes())
        signature = content.hexdigest()
        source_key = pack + '/' + key
        if signature in self.signatures:
            previous = self.signatures[signature]
            item = self.items[previous]
            if item['source_pack'] != pack or item['source_name'] != key:
                if source_key not in self.aliases: self.stats['duplicate_assets'] += 1
                self.aliases[source_key] = previous
            return previous
        ident = 'Supplemental_' + slug(pack)[:22] + '_' + slug(key)[:48] + '_' + hashlib.sha1(source_key.encode()).hexdigest()[:8]
        self.signatures[signature] = ident
        folder = OUT / slug(pack)
        scene = SCENES / slug(pack) / (ident + '.tscn')
        strip_width = width * longest
        columns = min(len(frames), max(1, 8192 // strip_width))
        rows = math.ceil(len(frames) / columns)
        if rows * height > 8192:
            raise ValueError(f'Asset atlas exceeds 8192 pixels: {source_key}')
        atlas = Image.new('RGBA', (columns * strip_width, rows * height))
        directions = {}
        image_path = folder / (ident + '.png')
        for index, (direction, sequence) in enumerate(frames.items()):
            x, y = (index % columns) * strip_width, (index // columns) * height
            for frame_index, frame in enumerate(sequence):
                atlas.paste(frame, (x + frame_index * width, y))
            anchor = anchors.get(direction, (width / 2, height - 8 * sum(footprint)))
            opaque = sequence[0].getbbox()
            contact = list(anchor) if category in ('Characters','Icons') else [width*.5, opaque[3] if opaque else height]
            directions[direction] = {'file': '../../' + image_path.relative_to(ROOT / 'assets').as_posix(),
                                     'region': [x, y, len(sequence) * width, height],
                                     'frame_width': width, 'frame_height': height, 'frames': len(sequence),
                                     'origin': list(anchor), 'footprint': list(footprint),
                                     'render_contact': contact,
                                     'grid_method': 'authored pivot and virtual footprint front',
                                     'grid_contact': [anchor[0] + 16 * (footprint[0] - footprint[1]),
                                                      anchor[1] + 8 * sum(footprint)]}
        image_path.parent.mkdir(parents=True, exist_ok=True)
        atlas.save(image_path, optimize=True)
        preferred = 'SE' if 'SE' in directions else next(iter(directions))
        info = directions[preferred]
        preview = frames[preferred][0].copy()
        box = preview.getbbox()
        if box:
            preview = preview.crop(box)
        preview.thumbnail((128, 128), Image.Resampling.NEAREST)
        preview_path = folder / (ident + '_preview.png')
        preview.save(preview_path, optimize=True)
        authored_behavior = behavior or {'layer': 'Decorations', 'building': False, 'door': False,
                                         'vehicle': False, 'ground': False, 'collision': 'box'}
        item = {'name': ident, 'display_name': label, 'category': 'Supplemental ' + category,
                'kind': 'obj', 'frames': info['frames'], 'fps': fps, 'directions': directions,
                'scene_path': res(scene), 'source_pack': pack, 'source_name': key,
                'source_files': list(sources), 'preview_path': res(preview_path),
                'default_scale': scale, 'content_hash': signature, 'behavior': authored_behavior,
                'import_tags': ['supplemental', category.lower(), 'directional views' if len(directions) > 1 else 'single view']}
        item.update(metadata or {})
        self.items[ident] = item
        area = info['region']
        body = f'''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/iso_object.gd" id="1"]
[ext_resource type="Texture2D" path={json.dumps('res://assets/' + info['file'].removeprefix('../../'))} id="2"]

[sub_resource type="AtlasTexture" id="AtlasTexture_view"]
atlas = ExtResource("2")
region = Rect2({area[0]}, {area[1]}, {area[2]}, {area[3]})
filter_clip = true

[node name={json.dumps(ident)} type="Node2D"]
y_sort_enabled = true
scale = Vector2({scale}, {scale})
script = ExtResource("1")
item_id = {json.dumps(ident)}
category = {json.dumps(item['category'])}
kind = "obj"
direction = {json.dumps(preferred)}
footprint = Vector2i({footprint[0]}, {footprint[1]})
origin_offset = Vector2({info['origin'][0]}, {info['origin'][1]})
total_frames = {info['frames']}
animation_fps = {fps}
has_collision = {'false' if authored_behavior['collision'] == 'none' else 'true'}
directions_data = {json.dumps(directions)}

[node name="Sprite2D" type="Sprite2D" parent="."]
texture = SubResource("AtlasTexture_view")
centered = false
offset = Vector2({-info['origin'][0]}, {-info['origin'][1]})
hframes = {info['frames']}
'''
        write(scene, body)
        self.stats['sprite_assets'] += 1
        self.stats['sprite_views'] += len(directions)
        self.stats['animated_assets'] += longest > 1
        return ident

    def notice(self, pack, source_folder, *, restricted=False, author='', url=''):
        notices = [p for p in source_folder.rglob('*.txt') if p.stem.lower() in ('license', 'licence')]
        text = '\n\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in notices)
        if text:
            write(OUT / slug(pack) / 'LICENSE.txt', text)
        return {'author': author, 'source_url': url,
                'license': 'See supplied LICENSE.txt' if text else 'No license notice supplied',
                'source_export_allowed': not restricted, 'license_files': [res(p) for p in notices]}

    def rotation_packs(self):
        definitions = [('2D_bonsai_tree_sprites_pack', 'Bonsai trees', '96px_', 30, (1, 1), .35, 'Nature'),
                       ('City_Builder_Village_Buildings', 'Village buildings', '96', 32, (3, 3), 1.0, 'Buildings'),
                       ('City_Builder_Water_Towers', 'Water towers', '64', 32, (2, 2), 1.0, 'Infrastructure')]
        for folder_name, pack, prefix, count, foot, scale, category in definitions:
            folder = RAW / folder_name
            metadata = self.notice(pack, folder, author='Polyy.AI', url='https://polyy.ai')
            before = len(self.items)
            for directory in sorted((folder / 'sprite').iterdir()):
                if not directory.name.startswith(prefix):
                    continue
                # A single canonical resolution keeps all artistic palettes/lightings without duplicate sizes.
                if folder_name != '2D_bonsai_tree_sprites_pack' and directory.name[len(prefix):] not in ('sun', 'studio', 'flat'):
                    continue
                lighting = directory.name[len(prefix):]
                for path in sorted(directory.glob('*.png')):
                    sheet = Image.open(path).convert('RGBA')
                    width, height = sheet.width // 8, sheet.height // 4
                    frames = [sheet.crop(((i % 8) * width, (i // 8) * height,
                                          (i % 8 + 1) * width, (i // 8 + 1) * height)) for i in range(count)]
                    views = {f'{i * 360 / count:g}': [frame] for i, frame in enumerate(frames)}
                    stem = path.stem.removeprefix('1x1_')
                    building = category == 'Buildings' and not any(s in stem for s in ('stone_well', 'wayside_shrine', 'market_stall'))
                    behavior = {'layer': 'Nature' if category == 'Nature' else 'Buildings', 'building': building,
                                'door': False, 'vehicle': False, 'ground': False, 'collision': 'box',
                                'walk': {'height': .8 if category == 'Nature' else 6.0}}
                    if building:
                        behavior['entrance_anchor'] = {'views': {direction: {'point': [foot[0] * .5, foot[1]],
                                                                            'arrival': [foot[0] * .5, foot[1] + 1]}
                                                                  for direction in views}}
                    self.sprite(pack, stem + '/' + lighting, human(stem) + ' · ' + human(lighting), views,
                                footprint=foot, scale=scale, category=category, behavior=behavior,
                                sources=[res(path)], metadata={**metadata, 'source_rotation_frames': count,
                                                              'source_resolution': directory.name})
            print(f'{pack}: {len(self.items) - before} catalog assets', flush=True)

    def kits(self):
        for folder in sorted(RAW.glob('36-*')):
            pack = human(folder.name.removeprefix('36-').removesuffix('-3d-pixel-art-kit')) + ' kit'
            metadata = self.notice(pack, folder, restricted=True, author='Antahonist', url='https://antahonist.itch.io')
            entries = json.loads((folder / 'manifest.json').read_text(encoding='utf-8'))
            for entry in entries:
                path = next(folder.rglob(entry['id'] + '_spin.png'))
                strip = Image.open(path).convert('RGBA'); count = entry['spin']['frames']
                width = strip.width // count; height = strip.height
                views = {f'{i * 360 / count:g}': [strip.crop((i * width, 0, (i + 1) * width, height))] for i in range(count)}
                name = entry['id']; extent = .8
                for needles, value in [('tent|tarp|hammock|canoe|greenhouse|trampoline|goal|slide', 2.8),
                                       ('shelf|shelving|wardrobe|bookcase|locker|refrigerator|whiteboard', 1.8),
                                       ('chair|desk|table|washer|dryer|cart|rack|stove|barbell|bench', 1.1),
                                       ('kettle|pot|bucket|backpack|cool_box|lamp|jerrycan', .55),
                                       ('bottle|cup|mug|canister|ball|toy|paddle|skillet', .3),
                                       ('spoon|fork|knife|compass|key|chalk|pen|dice|coin|eraser', .18)]:
                    if re.search(needles, name):
                        extent = value
                opaque = views['0'][0].getbbox(); size = max(opaque[2] - opaque[0], opaque[3] - opaque[1]) if opaque else width
                scale = min(4.0, extent * 32 / max(1, size))
                behavior = {'layer': 'Furniture', 'building': False, 'door': False, 'vehicle': False,
                            'ground': False, 'collision': 'none' if extent < .35 else 'box',
                            'walk': {'height': min(2.4, extent)}}
                self.sprite(pack, name, entry['name'], views, scale=scale, category='Furniture',
                            behavior=behavior, sources=[res(path)], metadata={**metadata, 'source_category': entry['category']})
            print(f'{pack}: {len(entries)} directional furniture assets', flush=True)

    def fleet(self):
        compass = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']
        for directory in sorted(RAW.glob('flipped-fleet-*')):
            folder = next(p for p in directory.iterdir() if p.is_dir())
            region = 'EU' if '-eu-' in directory.name else 'US'
            pack = 'Flipped Fleet ' + region
            metadata = self.notice(pack, folder, restricted=True, author='Filip Hron', url='https://rhinoflip.itch.io/')
            metadata['credit'] = 'Car sprites by Filip Hron · https://rhinoflip.itch.io/'
            for car in sorted(p for p in folder.iterdir() if p.is_dir()):
                paths = [car / f'{car.name}_{index:02}.png' for index in range(8)]
                if not all(path.exists() for path in paths):
                    continue
                views = {direction: [Image.open(path).convert('RGBA')] for direction, path in zip(compass, paths)}
                # Author pivot: frame centre + 11.5px down; native 4x2 cells at half scale = 4x2 metres.
                anchors = {direction: (64 - 8 * (4 - 2), 75.5 - 4 * (4 + 2)) for direction in compass}
                self.sprite(pack, car.name, human(car.name), views, anchors=anchors, footprint=(4, 2), scale=.5,
                            category='Vehicles', sources=[res(path) for path in paths], metadata=metadata,
                            behavior={'layer': 'Vehicles', 'building': False, 'vehicle': True, 'door': False,
                                      'ground': False, 'collision': 'box', 'walk': {'height': 1.5}})
            print(f'{pack}: prepared eight-direction vehicles', flush=True)

    def ships(self):
        folder = RAW / 'Ship' / 'Ship'
        directions = {'east': 'E', 'north-east': 'NE', 'north-west': 'NW', 'north': 'N',
                      'south-east': 'SE', 'south-west': 'SW', 'south': 'S', 'west': 'W'}
        metadata = self.notice('Pixel ships', folder)
        for ship in sorted(p for p in folder.iterdir() if p.is_dir()):
            views, sources = {}, []
            for name, direction in directions.items():
                path = ship / 'Idle/rotations' / (name + '.png')
                if path.exists():
                    views[direction] = [Image.open(path).convert('RGBA')]; sources.append(res(path))
            if views:
                self.sprite('Pixel ships', ship.name, human(ship.name.removeprefix('A_compact_')), views,
                            footprint=(2, 1), category='Watercraft', sources=sources, metadata=metadata,
                            behavior={'layer': 'Vehicles', 'building': False, 'vehicle': False, 'vehicle_kind':'watercraft','door': False,
                                      'ground': False, 'collision': 'none', 'walk': {'height': 1.2}})
        print('Pixel ships: prepared supplied compass rotations', flush=True)

    def korean(self):
        for name, pack in [('KoreanStreet_Free_Pack', 'Korean Street'), ('KoreanStreetRodeo_Free_Pack', 'Korean Street Rodeo')]:
            folder = RAW / name / name
            metadata = self.notice(pack, folder, restricted=True, author='usoljjang', url='https://usoljjang.itch.io/korean-street')
            for category, source_name in [('Buildings', 'buildings.json'), ('Props', 'props.json')]:
                entries = json.loads((folder / 'Data' / source_name).read_text(encoding='utf-8'))
                for entry in entries:
                    key = entry['name']; directory = next((p for p in (folder / category).iterdir() if p.is_dir() and (p.name == key or key.endswith(p.name))), folder / category)
                    animation = directory / (key + '_anim_1x.json')
                    animation = animation if animation.exists() else None
                    frames = []
                    if animation:
                        raw = json.loads(animation.read_text(encoding='utf-8'))
                        sheet_path = directory / (key + '_anim_sheet_1x.png'); sheet = Image.open(sheet_path).convert('RGBA')
                        for frame in raw['frames'].values():
                            rect = frame['frame']; x, y, w, h = (rect[k] for k in ('x', 'y', 'w', 'h'))
                            frames.append(sheet.crop((x, y, x + w, y + h)))
                        sources = [res(animation), res(sheet_path)]
                    else:
                        path = directory / (key + '_1x.png')
                        if not path.exists(): path = directory / (key + '.png')
                        frames = [Image.open(path).convert('RGBA')]; sources = [res(path)]
                    if category == 'Buildings':
                        footprint = (entry['cells_x'] * 4, entry['cells_y'] * 4)
                        point = entry['anchor_1x']; scale = .5
                    else:
                        footprint = (1, 1); scale = .5 if 'StringLights' in key else 1.0
                        point = entry.get('anchor_1x', [entry['anchor'][0] * .5, entry['anchor'][1] * .5])
                    anchor = (point[0] - 16 * (footprint[0] - footprint[1]), point[1] - 8 * sum(footprint))
                    behavior = {'layer': 'Buildings' if category == 'Buildings' else 'Decorations',
                                'building': category == 'Buildings', 'door': False, 'vehicle': False,
                                'ground': False, 'collision': 'none' if 'StringLights' in key else 'box',
                                'walk': {'height': entry.get('approx_height_m', 1.0)}}
                    if behavior['building']:
                        behavior['entrance_anchor'] = {'views': {'SW': {'point': [footprint[0] * .5, footprint[1]],
                                                                       'arrival': [footprint[0] * .5, footprint[1] + 2]}}}
                    self.sprite(pack, key, entry.get('en', human(key.removeprefix('KTown_'))), {'SW': frames},
                                anchors={'SW': anchor}, footprint=footprint, scale=scale, category=category,
                                fps=10.0, sources=sources, behavior=behavior, metadata={**metadata, 'authored_dimensions': entry})
            if (folder / 'Tiles').exists():
                for path in sorted((folder / 'Tiles').rglob('*_1x.png')):
                    image = Image.open(path).convert('RGBA')
                    self.sprite(pack, 'ground/' + path.stem, human(path.stem.removesuffix('_1x')), {'SE': [image]},
                                anchors={'SE': (image.width * .5, 0)}, footprint=(4, 4), scale=.5,
                                category='Ground', sources=[res(path)], metadata={**metadata, 'surface': 'ground', 'ground_shape': 'diamond'},
                                behavior={'layer': 'Ground', 'building': False, 'door': False, 'vehicle': False,
                                          'ground': True, 'collision': 'none'})
            print(f'{pack}: animated buildings, street props and supplied ground tiles prepared', flush=True)

    def save(self):
        self.stats['sprite_assets']=len(self.items)
        self.stats['sprite_views']=sum(len(item['directions']) for item in self.items.values())
        self.stats['animated_assets']=sum(any(view['frames']>1 for view in item['directions'].values()) for item in self.items.values())
        self.stats['character_families']=sum(item.get('kind')=='char' for item in self.items.values())
        self.stats['model_assets']=len(self.models)
        registry = {'version': 1, 'items': self.items, 'models': self.models, 'aliases': self.aliases,
                    'stats': dict(self.stats), 'notes': self.notes}
        write(REGISTRY, json.dumps(registry, ensure_ascii=False, indent=2))
        REPORT.mkdir(parents=True, exist_ok=True)
        write(REPORT / 'prepared_manifest.json', json.dumps(registry, ensure_ascii=False, indent=2))


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sprites', action='store_true')
    parser.add_argument('--korean', action='store_true')
    parser.add_argument('--extend', action='store_true')
    args = parser.parse_args()
    builder = Builder(args.extend)
    if args.sprites:
        builder.rotation_packs(); builder.kits(); builder.fleet(); builder.ships()
    if args.korean:
        builder.korean()
    if args.sprites or args.korean:
        builder.save(); print(json.dumps(dict(builder.stats)), flush=True)


if __name__ == '__main__':
    main()
