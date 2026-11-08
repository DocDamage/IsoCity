"""Compile reviewed zoning designs and frozen appearance members; never edit art."""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'resources/catalog/zoning_candidates.json'
THEMES = {
    'native': {'label': 'Match this world', 'note': 'Pixel City in the pixel world; HanX modern in the 3D world.'},
    'any': {'label': 'Any reviewed theme', 'note': 'May mix architectural styles and include locally restricted Korean source assets.'},
    'pixel_city': {'label': 'Pixel City', 'note': 'Supplied sprite buildings; flat artwork when used in 3D.'},
    'hanx_modern': {'label': 'HanX modern', 'note': 'Supplied native models; original dimensions and construction prices.'},
    'village': {'label': 'Village', 'note': 'Supplied village sprites, including saved palette and lighting appearances. Flat artwork in 3D.'},
    'historical': {'label': 'Historical village', 'note': 'Reviewed village buildings; no unrelated modern fillers. Flat artwork in 3D.'},
    'industrial': {'label': 'Industrial services', 'note': 'Vehicle care and workshop subjects. No reviewed housing or civic candidates in this theme.'},
    'korean_street': {'label': 'Korean street · local use', 'note': '2D zoning only: one home and three commercial subjects. Their flat 3D cards obscure ground-floor artwork. Source-project ZIP redistribution is restricted; no reviewed civic candidate.'},
}


def read(name):
    return json.loads((ROOT / 'resources/catalog' / name).read_text(encoding='utf-8'))


def compile_catalog():
    metadata = read('asset_metadata.json')['assets']
    registry = read('catalog_registry.json')
    available = {'2d:' + name for name in registry['items']}
    available.update(registry.get('models', {}))
    for name in ['imported_registry.json', 'supplemental_registry.json', 'swat_registry.json', 'reviewed_registry.json']:
        extra = read(name)
        available.update('2d:' + ident for ident in extra.get('items', {}))
        available.update(extra.get('models', {}))
    available.update('3d:' + p.parent.name + '/' + p.stem for p in (ROOT / 'scenes/items_3d').glob('*/*.tscn'))
    family_members = {}
    for ident, entry in metadata.items():
        if entry.get('family_id'):
            family_members.setdefault(entry['family_id'], []).append(ident)
    records = []

    def add(selector, zone, themes, density, price, cap, weight=1, modes=None):
        members = sorted(family_members[selector]) if selector in family_members else [selector]
        assert members and all(ident in available for ident in members), selector
        ident = selector if selector in family_members else 'asset/' + selector
        records.append({'id': ident, 'members': members, 'zone': zone, 'themes': themes,
                        'density': density, 'weight': weight, 'modes': modes or ['2d', '3d'],
                        'footprint_limit': cap, 'price_range': [price, price],
                        'requires_entrance': True})

    for name, density in [('House_Blue', 'low'), ('House_Brick', 'low'), ('House_Yellow', 'low'),
                          ('House_Mint_Garage', 'low'), ('House_Pink_Two_Story', 'medium'),
                          ('House_White_Modern', 'low'), ('Apartment_Brick', 'medium'), ('Apartment_Building', 'high')]:
        add('2d:' + name, 'residential', ['pixel_city'], density, 2000, [10, 10])
    for name, density, price in [('Row_Houses_A', 'low', 2000), ('Row_Houses_B', 'low', 2000),
                                  ('Apartment_4F_A', 'medium', 2000), ('Apartment_4F_B', 'medium', 2500),
                                  ('Apartment_6F_Balcony', 'high', 2500)]:
        add('3d:HanX_City/' + name, 'residential', ['hanx_modern'], density, price, [20, 20])
    for name in ['farmhouse_barn', 'longhouse', 'round_cottage', 'thatched_cottage', 'timber_frame_house']:
        add('supplemental/village/' + name, 'residential', ['village', 'historical'], 'low', 2000, [8, 8])
    for name in ['Coffee_Shop', 'Bakery', 'Bookstore', 'Supermarket']:
        add('2d:' + name, 'commercial', ['pixel_city'], 'low', 3000, [10, 12])
    add('3d:HanX_City/Cafe_Small', 'commercial', ['hanx_modern'], 'low', 3000, [20, 12])
    for name in ['Bakery', 'Boutique', 'Butcher', 'Cafe', 'Florist', 'Grocery', 'Ice_Cream', 'Pharmacy']:
        add('3d:HanX_Shop/Shop_' + name, 'commercial', ['hanx_modern'], 'low', 2500, [20, 20])
    for name in ['apothecary', 'bakery', 'tavern_inn']:
        add('supplemental/village/' + name, 'commercial', ['village', 'historical'], 'low', 3000, [8, 8])
    add('supplemental/village/blacksmith_forge', 'commercial', ['village', 'historical'], 'low', 3500, [8, 8])
    add('3d:HanX_City/Office_Tower', 'commercial', ['hanx_modern'], 'high', 3500, [36, 36])
    for name in ['Car_Wash', 'Gas_Station_Store', 'Repair_Garage']:
        add('3d:HanX_GasStation/' + name, 'commercial', ['industrial'], 'low', 2500, [28, 24])
    for name in ['Hopital', 'Police']:
        # The supplied hospital is 66 ground units wide in its native pixel
        # world, beyond the existing 64-unit lot limit. Keep its natural size;
        # its 33-unit flat representation fits 3D lots. Manual placement stays available.
        add('2d:' + name, 'civic', ['pixel_city'], 'medium', 5000, [48, 48],
            modes=['3d'] if name == 'Hopital' else ['2d', '3d'])
    for name, density in [('School_Building', 'high'), ('Kindergarten_Building', 'medium'), ('Gym_Building', 'medium')]:
        add('3d:HanX_School/' + name, 'civic', ['hanx_modern'], density, 2500, [64, 64])
    for name in ['village_hall', 'stone_chapel', 'watchtower']:
        add('supplemental/village/' + name, 'civic', ['village', 'historical'], 'low', 3500, [8, 8])
    korean = [
        ('2d:Supplemental_Korean_Street_KTown_House_Dasedae_02_456f71b3', 'residential', 2000),
        ('2d:Supplemental_Korean_Street_KTown_Store_Convenience_01_23704d1e', 'commercial', 3000),
        ('2d:Supplemental_Korean_Street_Rodeo_KTown_Rodeo_MoonCafeNoodle_13_439b4de9', 'commercial', 3000),
        ('2d:Supplemental_Korean_Street_Rodeo_KTown_Rodeo_YellowPochaCafe_10_06b6d33c', 'commercial', 3000),
    ]
    for ident, zone, price in korean:
        add(ident, zone, ['korean_street'], 'medium', price, [16, 16], modes=['2d'])
    records.sort(key=lambda item: item['id'])
    assert len({entry['id'] for entry in records}) == len(records)
    dependencies = ['asset_metadata.json', 'asset_behaviors.json', 'economy.json', 'model_grid_bounds.json',
                    'catalog_registry.json', 'asset_style_models.json', 'imported_registry.json',
                    'supplemental_registry.json', 'swat_registry.json', 'reviewed_registry.json']
    sources = {name: hashlib.sha256((ROOT / 'resources/catalog' / name).read_bytes()).hexdigest()
               for name in dependencies}
    result = {'version': 1, 'selection_version': 'family_weighted_v1', 'themes': THEMES,
              'sources': sources, 'families': records}
    result['revision'] = hashlib.sha256(json.dumps(result, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    return result


def main():
    result = compile_catalog()
    encoded = json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + '\n'
    if '--check' in sys.argv:
        if not DEST.is_file() or DEST.read_text(encoding='utf-8') != encoded:
            raise SystemExit('Zoning candidate catalog is stale; review and regenerate it.')
    else:
        DEST.write_text(encoded, encoding='utf-8')
    print(f"ZONING CANDIDATES: {len(result['families'])} reviewed designs, "
          f"{sum(len(row['members']) for row in result['families'])} concrete appearances; "
          f"revision {result['revision'][:12]}")


if __name__ == '__main__':
    main()
