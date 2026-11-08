"""Calibrate clear opaque building bases; shadows never determine the anchor.

The prepared PNG stays unchanged so saved per-pixel color masks remain valid.
The sprite receives an affine projection from its measured base to the 2:1 grid.
"""
import json
import math
import re
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
VERSION = 1


def measure_base(image):
    mask = np.asarray(image.convert('RGBA'))[:, :, 3] >= 240
    xs = np.where(mask.any(axis=0))[0]
    if len(xs) < 32: return None
    bottom = mask.shape[0] - 1 - np.argmax(mask[::-1, :], axis=0)
    tip = np.median(xs[bottom[xs] >= bottom[xs].max() - 1])
    fits = []
    for side in [-1, 1]:
        radius = tip - xs.min() if side < 0 else xs.max() - tip
        if radius < 16: return None
        fit_x = xs[(xs > tip - radius * .85) & (xs < tip - radius * .12)] if side < 0 else xs[(xs > tip + radius * .12) & (xs < tip + radius * .85)]
        for _ in range(5):
            if len(fit_x) < 10: return None
            slope, intercept = np.polyfit(fit_x, bottom[fit_x], 1)
            error = bottom[fit_x] - (slope * fit_x + intercept)
            median = np.median(error)
            deviation = np.median(abs(error - median))
            fit_x = fit_x[abs(error - median) < max(1.5, deviation * 2.5)]
        if not .45 <= slope * -side <= .7: return None
        candidates = xs[xs < tip] if side < 0 else xs[xs > tip]
        inliers = candidates[abs(bottom[candidates] - (slope * candidates + intercept)) < 2.5]
        if len(inliers) < radius * .4: return None
        edge = inliers.min() if side < 0 else inliers.max()
        fits.append((slope, intercept, edge))
    (ml, bl, xl), (mr, br, xr) = fits
    bx = (br - bl) / (ml - mr)
    left = np.array([xl, ml * xl + bl])
    right = np.array([xr, mr * xr + br])
    front = np.array([bx, ml * bx + bl])
    if min(front[0] - left[0], right[0] - front[0]) < 16: return None
    return left, front, right


def calibrate(registry):
    calibrated, skipped = [], []
    for item in registry['items'].values():
        if item.get('source_pack') != 'Brutalist Metropole v1.1.2' or not item['category'].endswith('Buildings'): continue
        scale = item['default_scale']
        for view in item['directions'].values():
            image = Image.open(ROOT / 'assets' / view['file'].removeprefix('../../'))
            base = measure_base(image)
            if base is None:
                skipped.append(item['name'])
                continue
            left, front, right = base
            # Whole default-size cells keep adjoining buildings on the same grid.
            fx = round(max(1, math.ceil((front[0] - left[0]) * scale / 16 - .1)) / scale)
            fy = round(max(1, math.ceil((right[0] - front[0]) * scale / 16 - .1)) / scale)
            matrix = np.array([[16 * fx, -16 * fy], [8 * fx, 8 * fy]]) @ np.linalg.inv(np.column_stack((front - left, front - right)))
            if abs(matrix[0, 1]) > .12 or np.linalg.det(matrix) <= 0:
                skipped.append(item['name'])
                continue
            origin = left + right - front
            view['origin'] = origin.round(6).tolist()
            view['footprint'] = [fx, fy]
            view['alignment_transform'] = [float(matrix[0, 0]), float(matrix[1, 0]), float(matrix[0, 1]), float(matrix[1, 1])]
            view['alignment_base'] = [left.round(6).tolist(), front.round(6).tolist(), right.round(6).tolist()]
            view['alignment_version'] = VERSION
            calibrated.append(item['name'])
        scene = ROOT / item['scene_path'].removeprefix('res://')
        text = scene.read_text(encoding='utf-8')
        preferred = item['directions'].get('SE', next(iter(item['directions'].values())))
        text = re.sub(r'^origin_offset = .+$', f"origin_offset = Vector2({preferred['origin'][0]}, {preferred['origin'][1]})", text, flags=re.M)
        text = re.sub(r'^footprint = .+$', f"footprint = Vector2i({preferred['footprint'][0]}, {preferred['footprint'][1]})", text, flags=re.M)
        text = re.sub(r'^directions_data = .+$', lambda _: 'directions_data = ' + json.dumps(item['directions']), text, flags=re.M)
        text = re.sub(r'^offset = .+$', f"offset = Vector2({-preferred['origin'][0]}, {-preferred['origin'][1]})", text, flags=re.M)
        if scene.read_text(encoding='utf-8') != text: scene.write_text(text, encoding='utf-8')
    registry['alignment_calibration'] = {'version': VERSION, 'calibrated': calibrated, 'estimated': skipped}
    return calibrated, skipped


if __name__ == '__main__':
    path = ROOT / 'resources/catalog/imported_registry.json'
    registry = json.loads(path.read_text(encoding='utf-8'))
    calibrated, skipped = calibrate(registry)
    path.write_text(json.dumps(registry, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'Calibrated {len(calibrated)} building views; retained estimates for {len(skipped)} irregular bases.')
