"""Audit every catalog view and calibrate imported geometry without changing pixels.

Rectangular bases use a measured affine projection. Irregular silhouettes use a
documented contact anchor; they are never presented as measured rectangular art.
"""
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE_GRIDS = {'CATS ISOMETRIC ASSET PACK': (32, 32), 'isometricStrategy': (64, 64), 'rodwan_tileset2': (32, 16), 'water tileset by Rodwan': (32, 16), 'Rodwan_Cliffs': (32, 32)}


def source_cell(item):
    pack = item.get('source_pack')
    match = re.search(r'/r(\d+)_c(\d+)$', item.get('source_name', ''))
    if pack not in SOURCE_GRIDS or not match or 'sliced tile' not in item.get('import_tags', []): return None
    width, height = SOURCE_GRIDS[pack]
    if pack == 'CATS ISOMETRIC ASSET PACK' and item['source_name'].startswith('half_blocks/'): height = 24
    source = Image.open(ROOT / item['source_files'][0].removeprefix('res://')).convert('RGBA')
    row, column = (int(v) - 1 for v in match.groups())
    piece = source.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
    return width, height, piece.getchannel('A').getbbox()


def shared_canvases(items):
    """Recover the common camera/cell of modular pieces before individual crops."""
    groups, result = defaultdict(list), {}
    for ident, item in items.items():
        sources = item.get('source_files', [])
        if not item.get('source_pack') or len(sources) != 1 or item.get('import_tags'): continue
        path = ROOT / sources[0].removeprefix('res://')
        if path.suffix.lower() != '.png': continue
        name = path.stem.lower()
        family = next((word for word in ['tiled ground', 'canal', 'pipe', 'pavement', 'road', 'floor', 'shore', 'terrain', 'wall', 'path'] if name.startswith(word)), None)
        if not family: continue
        with Image.open(path) as image:
            groups[(item['source_pack'], str(path.parent), image.size, family)].append((ident, path))
    for key, entries in groups.items():
        if len(entries) < 3: continue
        size = key[2]
        union = np.zeros((size[1], size[0]), dtype=np.uint8)
        crops, effective = {}, []
        for ident, path in entries:
            image = Image.open(path).convert('RGBA')
            alpha = np.asarray(image.getchannel('A'))
            union = np.maximum(union, alpha)
            box = image.getchannel('A').getbbox()
            if not box: continue
            crops[ident] = box
            view = items[ident]['directions'].get('SE', next(iter(items[ident]['directions'].values())))
            factor = view['frame_width'] / (box[2] - box[0])
            effective.append(factor * items[ident].get('default_scale', 1))
        picture = Image.new('RGBA', size)
        picture.putalpha(Image.fromarray(union))
        base = solid_base(picture)
        if base is None and key[3] in ['canal', 'tiled ground']:
            # Curved modular banks deliberately protrude beyond straight diamond
            # edges. Their shared canvas still exposes its four cell extremities.
            ys, xs = np.where(union >= 240)
            if len(xs):
                left = np.array([float(xs.min()), float(np.median(ys[xs <= xs.min() + 1]))])
                right = np.array([float(xs.max() + 1), float(np.median(ys[xs >= xs.max() - 1]))])
                front = np.array([float(np.median(xs[ys >= ys.max() - 1])) + .5, float(ys.max() + 1)])
                if abs(left[1] - right[1]) < size[1] * .03 and abs((left[1] + right[1]) * .5 - (ys.min() + ys.max()) * .5) < size[1] * .08 and abs(front[0] - (left[0] + right[0]) * .5) < size[0] * .05:
                    base = (left, front, right)
        if base is None: continue
        left, front, right = base
        if right[0] - left[0] < size[0] * .6: continue
        reference_scale = float(np.median(effective))
        cells = [max(1, math.ceil((front[0] - left[0]) * reference_scale / 16 - .1)), max(1, math.ceil((right[0] - front[0]) * reference_scale / 16 - .1))]
        for ident, _path in entries:
            if ident in crops: result[ident] = {'base': base, 'crop': crops[ident], 'cells': cells, 'family': key[3]}
    return result


def texture_path(view):
    file = view['file']
    return ROOT / 'assets' / file[6:] if file.startswith('../../') else ROOT / 'assets/pixel_isometric' / file


def solid_base(image):
    alpha = np.asarray(image.getchannel('A'))
    mask = alpha >= max(40, min(240, int(alpha.max())))
    xs = np.flatnonzero(mask.any(axis=0))
    if len(xs) < 12: return None
    bottom = mask.shape[0] - 1 - np.argmax(mask[::-1], axis=0)
    tip = float(np.median(xs[bottom[xs] >= bottom[xs].max() - 1]))
    fits = []
    for side in [-1, 1]:
        radius = tip - xs.min() if side < 0 else xs.max() - tip
        if radius < 6: return None
        candidates = xs[(xs > tip - radius * .94) & (xs < tip - radius * .08)] if side < 0 else xs[(xs > tip + radius * .08) & (xs < tip + radius * .94)]
        fit_x = candidates.copy()
        for _ in range(5):
            if len(fit_x) < 5: return None
            slope, intercept = np.polyfit(fit_x, bottom[fit_x], 1)
            error = bottom[fit_x] - (slope * fit_x + intercept)
            mad = np.median(abs(error - np.median(error)))
            fit_x = fit_x[abs(error - np.median(error)) <= max(1.15, mad * 2.5)]
        if not .22 <= slope * -side <= 1.05: return None
        inliers = candidates[abs(bottom[candidates] - (slope * candidates + intercept)) < 1.6]
        if len(inliers) < radius * .65: return None
        if np.ptp(inliers) < radius * .65: return None
        edge = inliers.min() if side < 0 else inliers.max()
        fits.append((slope, intercept, edge))
    (ml, bl, xl), (mr, br, xr) = fits
    bx = (br - bl) / (ml - mr)
    left, right = np.array([xl, ml * xl + bl]), np.array([xr, mr * xr + br])
    front = np.array([bx, ml * bx + bl])
    if min(front[0] - left[0], right[0] - front[0]) < 6: return None
    return left, front, right


def write_scene(item, ident):
    category = item['category']
    relative = item.get('scene_path')
    if relative:
        path = ROOT / relative.removeprefix('res://')
    elif category.startswith('RPG_'):
        path = ROOT / 'scenes/items/RPG_World' / category[4:] / (ident + '.tscn')
    else:
        path = ROOT / 'scenes/items' / category.replace(' & ', '_').replace(' ', '_') / (ident + '.tscn')
    text = path.read_text(encoding='utf-8')
    view = item['directions'].get('SE', next(iter(item['directions'].values())))
    replacements = {
        'directions_data': json.dumps(item['directions']),
        'origin_offset': 'Vector2(%s, %s)' % tuple(view['origin']),
        'footprint': 'Vector2i(%s, %s)' % tuple(view['footprint']),
        'offset': 'Vector2(%s, %s)' % tuple(-v for v in view['origin']),
    }
    for key, value in replacements.items():
        text = re.sub(r'^' + key + r' = .+$', lambda _: key + ' = ' + value, text, flags=re.M)
    if text != path.read_text(encoding='utf-8'): path.write_text(text, encoding='utf-8')


def audit(apply=False):
    rows, errors, samples = [], [], defaultdict(list)
    counts = Counter()
    for filename in ['catalog_registry.json', 'imported_registry.json']:
        path = ROOT / 'resources/catalog' / filename
        registry = json.loads(path.read_text(encoding='utf-8'))
        shared = shared_canvases(registry['items'])
        for ident, item in registry['items'].items():
            authored = not item.get('source_pack') and not item['category'].startswith('RPG_')
            scale = float(item.get('default_scale', 1))
            pack = item.get('source_pack', 'Original ' + item['category'].split('_')[0])
            cell = source_cell(item)
            source_name = item.get('source_name', '').replace('\\', '/').lower()
            if item.get('source_pack') == 'Wave_shore tiles by Rodwan' or ('/tile/' in '/' + source_name and 'alltils' not in source_name):
                item['surface'] = 'ground'
                item['ground_shape'] = 'square' if item['directions'].get('SE', next(iter(item['directions'].values())))['frame_width'] == item['directions'].get('SE', next(iter(item['directions'].values())))['frame_height'] else 'diamond'
            for direction, view in item.get('directions', {}).items():
                try:
                    raw = Image.open(texture_path(view)).convert('RGBA')
                    width, height = int(view.get('frame_width', raw.width)), int(view.get('frame_height', raw.height))
                    assert width > 0 and height > 0 and raw.width % width == 0
                    frames = [raw.crop((x, 0, x + width, height)) for x in range(0, raw.width, width)]
                    # One common anchor for every frame avoids walking/animation jitter.
                    union = frames[0].copy()
                    alpha = np.maximum.reduce([np.asarray(f.getchannel('A')) for f in frames])
                    union.putalpha(Image.fromarray(alpha))
                    ys, xs = np.where(alpha >= max(40, min(240, int(alpha.max()))))
                    assert len(xs), 'No visible pixels'
                    method = 'authored'
                    if not authored:
                        view.setdefault('grid_original', {k: view[k] for k in ['origin', 'footprint']})
                        base = solid_base(union) if len(frames) == 1 else None
                        # Keep bases already verified in the Brutalist integration suite.
                        if view.get('alignment_base') and (view.get('alignment_version') == 1 or view.get('grid_method') == 'measured base'):
                            base = tuple(np.array(p) for p in view['alignment_base'])
                        ground = item.get('surface') == 'ground' or item.get('kind') == 'tile'
                        opaque_rect = alpha.min() >= 240
                        if ident in shared:
                            reference = shared[ident]
                            box = reference['crop']
                            factor = np.array([width / (box[2] - box[0]), height / (box[3] - box[1])])
                            source_base = [(p - np.array(box[:2])) * factor for p in reference['base']]
                            left, front, right = source_base
                            fx, fy = [round(c / scale) for c in reference['cells']]
                            origin = left + right - front
                            matrix = np.array([[16 * fx, -16 * fy], [8 * fx, 8 * fy]]) @ np.linalg.inv(np.column_stack((front - left, front - right)))
                            method = 'shared source canvas'
                        elif cell:
                            # Import cropping removed transparent padding. Recover its original
                            # cell coordinates so partial edges retain exactly the same phase.
                            cell_width, cell_height, box = cell
                            factor_x, factor_y = width / (box[2] - box[0]), height / (box[3] - box[1])
                            fx = fy = round(max(1, round(cell_width * scale / 32)) / scale)
                            origin = np.array([(cell_width * .5 - box[0]) * factor_x, (cell_height - cell_width * .5 - box[1]) * factor_y])
                            matrix = np.diag([32 * fx / (cell_width * factor_x), 16 * fy / (cell_width * .5 * factor_y)])
                            source_base = [origin + np.array([-cell_width * .5 * factor_x, cell_width * .25 * factor_y]), origin + np.array([0, cell_width * .5 * factor_y]), origin + np.array([cell_width * .5 * factor_x, cell_width * .25 * factor_y])]
                            method = 'source tile cell'
                        elif ground and opaque_rect:
                            # Square/top-down textures are explicitly projected as floor diamonds.
                            cells = max(1, round(width * scale / 32))
                            fx = fy = round(cells / scale)
                            matrix = np.array([[16 * fx / width, -16 * fy / height], [8 * fx / width, 8 * fy / height]])
                            origin = np.array([0., 0.])
                            source_base = [np.array([0, height]), np.array([width, height]), np.array([width, 0])]
                            method = 'square floor'
                        elif ground and 1.5 <= width / height <= 2.6:
                            cells = max(1, round((xs.max() - xs.min() + 1) * scale / 32))
                            fx = fy = round(cells / scale)
                            left = np.array([float(xs.min()), (ys.min() + ys.max() + 1) * .5])
                            front = np.array([(xs.min() + xs.max() + 1) * .5, float(ys.max() + 1)])
                            right = np.array([float(xs.max() + 1), left[1]])
                            origin = left + right - front
                            matrix = np.array([[16 * fx, -16 * fy], [8 * fx, 8 * fy]]) @ np.linalg.inv(np.column_stack((front - left, front - right)))
                            source_base = [left, front, right]
                            method = 'floor bounds'
                        elif base is not None:
                            left, front, right = base
                            fx = round(max(1, math.ceil((front[0] - left[0]) * scale / 16 - .1)) / scale)
                            fy = round(max(1, math.ceil((right[0] - front[0]) * scale / 16 - .1)) / scale)
                            matrix = np.array([[16 * fx, -16 * fy], [8 * fx, 8 * fy]]) @ np.linalg.inv(np.column_stack((front - left, front - right)))
                            if abs(matrix[0, 1]) > .3 or np.linalg.det(matrix) <= 0: base = None
                            else:
                                origin = left + right - front
                                source_base = base
                                method = 'measured base'
                        if method == 'authored':
                            # An irregular prop has a contact point, not four straight base edges.
                            low = ys.max()
                            contact_x = float(np.median(xs[ys >= low - max(1, round(height * .012))]))
                            support = xs[ys >= low - max(2, round(height * .12), round(width * .25))]
                            support_width = max(1, np.percentile(support, 95) - np.percentile(support, 5))
                            if item['category'].endswith(('Buildings', 'Blocks')): support_width = xs.max() - xs.min() + 1
                            cells = max(1, round(support_width * scale / 32))
                            fx = fy = round(cells / scale)
                            origin = np.array([contact_x, float(low) - 16 * fx])
                            matrix = np.eye(2)
                            source_base = None
                            method = 'contact anchor'
                        view['origin'] = np.round(origin, 6).tolist()
                        view['footprint'] = [fx, fy]
                        view['alignment_transform'] = [float(matrix[0, 0]), float(matrix[1, 0]), float(matrix[0, 1]), float(matrix[1, 1])]
                        if source_base is not None: view['alignment_base'] = [np.round(p, 6).tolist() for p in source_base]
                        else: view.pop('alignment_base', None)
                        view['alignment_version'] = 2
                    view['grid_method'] = method
                    # Every view receives an explicit, testable grounding contract.
                    view['grid_contact'] = [view['origin'][0] + 16 * (view['footprint'][0] - view['footprint'][1]), view['origin'][1] + 8 * sum(view['footprint'])] if authored else ([float(contact_x), float(low)] if method == 'contact anchor' else list(map(float, source_base[1])))
                    counts[method] += 1
                    row = {'asset': '2d:' + ident, 'view': direction, 'pack': pack, 'method': method, 'origin': view['origin'], 'footprint': view['footprint'], 'default_scale': scale, 'frames': len(frames)}
                    rows.append(row)
                    if direction == ('SE' if 'SE' in item['directions'] else next(iter(item['directions']))) and len(samples[pack]) < 5:
                        samples[pack].append((frames[0], view.copy(), item.get('display_name', ident)))
                except Exception as error:
                    errors.append({'asset': ident, 'view': direction, 'error': str(error)})
            if apply: write_scene(item, ident)
        if apply: path.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding='utf-8')
    report = {'sprite_assets': len({r['asset'] for r in rows}), 'sprite_views': len(rows), 'methods': dict(counts), 'errors': errors, 'views': rows}
    out = ROOT / 'output/asset_grid_audit'
    out.mkdir(parents=True, exist_ok=True)
    (out / 'sprites.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    # Browse every pack with its actual projected footprint/contact overlaid.
    for page, packs in enumerate([list(samples)[i:i + 8] for i in range(0, len(samples), 8)]):
        sheet = Image.new('RGB', (1200, len(packs) * 190), '#182735')
        draw = ImageDraw.Draw(sheet)
        for row_index, pack in enumerate(packs):
            for column, (picture, view, name) in enumerate(samples[pack]):
                matrix = np.array(view.get('alignment_transform', [1, 0, 0, 1])).reshape(2, 2).T
                origin = np.array(view['origin'])
                corners = np.array([[0, 0], [picture.width, 0], [0, picture.height], [picture.width, picture.height]])
                projected = (corners - origin) @ matrix.T
                minimum, maximum = projected.min(axis=0), projected.max(axis=0)
                zoom = min(205 / max(1, maximum[0] - minimum[0]), 137 / max(1, maximum[1] - minimum[1]))
                position = np.array([column * 240 + 115, row_index * 190 + 162]) - np.array([(minimum[0] + maximum[0]) * .5, maximum[1]]) * zoom
                inverse = np.linalg.inv(matrix * zoom)
                translation = origin - inverse @ position
                art = picture.transform(sheet.size, Image.Transform.AFFINE, tuple(np.column_stack((inverse, translation)).reshape(-1)), Image.Resampling.NEAREST)
                sheet.paste(art, (0, 0), art)
                fx, fy = view['footprint']
                foot = [(0, 0), (16 * fx, 8 * fx), (16 * (fx - fy), 8 * (fx + fy)), (-16 * fy, 8 * fy), (0, 0)]
                draw.line([tuple(np.array(p) * zoom + position) for p in foot], fill='#61f4cf', width=1)
                draw.text((column * 240 + 5, row_index * 190 + 3), pack[:34], fill='white')
                draw.text((column * 240 + 5, row_index * 190 + 172), view['grid_method'], fill='#61f4cf')
        sheet.save(out / f'pack_bases_{page + 1}.png')
    print(json.dumps({k:v for k,v in report.items() if k != 'views'}, indent=2))
    if errors: raise SystemExit(1)
    return report


if __name__ == '__main__':
    import sys
    audit('--apply' in sys.argv)
