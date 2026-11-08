"""Recreate imported pixels from originals in memory; never rewrite the PNGs.

The old catalog hash predates alpha compositing, so it includes invisible RGB
values that PNG preparation deliberately clears. Compare the actual prepared
pixels instead of using that earlier intermediate hash.
"""
import json
from pathlib import Path
from PIL import Image
import import_extra_assets as importer

ROOT = Path(__file__).resolve().parents[1]
registry = json.loads((ROOT / 'resources/catalog/imported_registry.json').read_text(encoding='utf-8'))
errors, compared = [], []
def compare_image(expected, path):
    if not path.exists():
        errors.append(str(path.relative_to(ROOT)))
        return
    actual = Image.open(path).convert('RGBA')
    if actual.size != expected.size or actual.tobytes() != expected.tobytes(): errors.append(str(path.relative_to(ROOT)))
    compared.append(str(path.relative_to(ROOT)))

importer.write_image = compare_image
importer.write_text = lambda *_: None
for pack in registry['source_packs']:
    importer.process_pack(ROOT / 'assets' / pack)
assert set(importer.items) == set(registry['items']), 'Source asset inventory changed'
report = {'assets': len(registry['items']), 'images': len(compared), 'changed_images': errors}
(ROOT / 'output/asset_grid_audit/pixel_integrity.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(f"PIXEL INTEGRITY: {len(registry['items'])} assets, {len(compared)} images, {len(errors)} changed images")
raise SystemExit(1 if errors else 0)
