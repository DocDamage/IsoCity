import os
import json
import re
import glob
from pathlib import Path
from PIL import Image

def sanitize_name(name):
    clean = re.sub(r'[^\w\-_]', '_', name)
    clean = re.sub(r'_+', '_', clean).strip('_')
    return clean

def main():
    os.chdir(Path(__file__).resolve().parents[1])
    print("=== Building Complete IsoCity Asset Pipeline ===")
    
    with open('assets/pixel_isometric/items.json', 'r', encoding='utf-8') as f:
        catalog = json.load(f)

    os.makedirs('resources/catalog', exist_ok=True)
    os.makedirs('resources/tilesets', exist_ok=True)
    os.makedirs('scenes/items', exist_ok=True)
    os.makedirs('scenes/items_3d', exist_ok=True)

    registry = {
        "categories": list(catalog.get("categories", [])),
        "items": {},
        "by_category": {},
        "tilesets": catalog.get("tilesets", {})
    }

    for cat in registry["categories"]:
        registry["by_category"][cat] = []

    # 1. Generate 2D scenes for PixelIsometric
    count_2d = 0
    for item in catalog.get("items", []):
        iid = item.get("name", "")
        cat = item.get("category", "")
        kind = item.get("kind", "obj")
        frames = item.get("frames", 1)
        fps = item.get("fps", 4.0)
        dirs = item.get("directions", {})

        registry["items"][iid] = item
        if cat not in registry["by_category"]:
            registry["by_category"][cat] = []
        registry["by_category"][cat].append(iid)

        pref_dir = "SE" if "SE" in dirs else (list(dirs.keys())[0] if dirs else "SE")
        dinfo = dirs.get(pref_dir, {})
        rel_file = dinfo.get("file", "")
        origin = dinfo.get("origin", [0, 0])
        footprint = dinfo.get("footprint", [1, 1])

        tex_path = f"res://assets/pixel_isometric/{rel_file}" if rel_file else ""
        cat_folder = sanitize_name(cat)
        target_dir = os.path.join('scenes', 'items', cat_folder)
        os.makedirs(target_dir, exist_ok=True)
        tscn_file = os.path.join(target_dir, f"{iid}.tscn")

        dirs_json = json.dumps(dirs)

        is_char = (cat == "Characters" or kind == "char" or cat == "Pets" or kind == "pet")

        if is_char:
            is_pet_bool = "true" if (cat == "Pets" or kind == "pet") else "false"
            ext_resources = [
                '[ext_resource type="Script" path="res://scripts/iso_character.gd" id="1_char_script"]'
            ]
            if tex_path:
                ext_resources.append(f'[ext_resource type="Texture2D" path="{tex_path}" id="2_tex"]')

            sub_resources = [
                '[sub_resource type="CircleShape2D" id="CircleShape2D_char"]',
                'radius = 5.0'
            ]

            tscn_lines = [
                f'[gd_scene load_steps={len(ext_resources) + len(sub_resources)} format=3]',
                ''
            ]
            tscn_lines.extend(ext_resources)
            tscn_lines.append('')
            tscn_lines.extend(sub_resources)
            tscn_lines.append('')
            tscn_lines.append(f'[node name="{iid}" type="CharacterBody2D"]')
            tscn_lines.append('y_sort_enabled = true')
            tscn_lines.append('script = ExtResource("1_char_script")')
            tscn_lines.append(f'item_id = "{iid}"')
            tscn_lines.append(f'direction = "{pref_dir}"')
            tscn_lines.append(f'origin_offset = Vector2({origin[0]}, {origin[1]})')
            tscn_lines.append(f'is_pet = {is_pet_bool}')
            tscn_lines.append(f'directions_data = {dirs_json}')
            tscn_lines.append('')
            tscn_lines.append('[node name="CollisionShape2D" type="CollisionShape2D" parent="."] ')
            tscn_lines.append('shape = SubResource("CircleShape2D_char")')
            tscn_lines.append('')
            tscn_lines.append('[node name="Sprite2D" type="Sprite2D" parent="."] ')
            if tex_path:
                tscn_lines.append('texture = ExtResource("2_tex")')
            tscn_lines.append('centered = false')
            tscn_lines.append(f'offset = Vector2({-origin[0]}, {-origin[1]})')
            tscn_lines.append(f'hframes = {max(1, frames)}')
            tscn_lines.append('')
        else:
            # Standard IsoObject with StaticBody2D collision for solid items
            ext_resources = [
                '[ext_resource type="Script" path="res://scripts/iso_object.gd" id="1_script"]'
            ]
            if tex_path:
                ext_resources.append(f'[ext_resource type="Texture2D" path="{tex_path}" id="2_tex"]')

            has_col = (kind in ["build", "obj", "wall"] and cat not in ["Wall Decor", "Floors"])
            col_lines = []
            if has_col:
                # 4 diamond corners
                w_x = 16 * footprint[0]
                w_y = 8 * footprint[0]
                b_x = 16 * (footprint[0] - footprint[1])
                b_y = 8 * (footprint[0] + footprint[1])
                l_x = -16 * footprint[1]
                l_y = 8 * footprint[1]
                poly_str = f"PackedVector2Array(0, 0, {w_x}, {w_y}, {b_x}, {b_y}, {l_x}, {l_y})"
                col_lines = [
                    '[node name="StaticBody2D" type="StaticBody2D" parent="."] ',
                    '',
                    '[node name="CollisionPolygon2D" type="CollisionPolygon2D" parent="StaticBody2D"] ',
                    f'polygon = {poly_str}',
                    ''
                ]

            tscn_lines = [
                f'[gd_scene load_steps={len(ext_resources) + 1} format=3]',
                ''
            ]
            tscn_lines.extend(ext_resources)
            tscn_lines.append('')
            tscn_lines.append(f'[node name="{iid}" type="Node2D"]')
            tscn_lines.append('y_sort_enabled = true')
            tscn_lines.append('script = ExtResource("1_script")')
            tscn_lines.append(f'item_id = "{iid}"')
            tscn_lines.append(f'category = "{cat}"')
            tscn_lines.append(f'kind = "{kind}"')
            tscn_lines.append(f'direction = "{pref_dir}"')
            tscn_lines.append(f'footprint = Vector2i({footprint[0]}, {footprint[1]})')
            tscn_lines.append(f'origin_offset = Vector2({origin[0]}, {origin[1]})')
            tscn_lines.append(f'total_frames = {frames}')
            tscn_lines.append(f'animation_fps = {fps}')
            tscn_lines.append(f'has_collision = {"true" if has_col else "false"}')
            tscn_lines.append(f'directions_data = {dirs_json}')
            tscn_lines.append('')
            tscn_lines.append('[node name="Sprite2D" type="Sprite2D" parent="."] ')
            if tex_path:
                tscn_lines.append('texture = ExtResource("2_tex")')
            tscn_lines.append('centered = false')
            tscn_lines.append(f'offset = Vector2({-origin[0]}, {-origin[1]})')
            tscn_lines.append(f'hframes = {max(1, frames)}')
            tscn_lines.append('')
            tscn_lines.extend(col_lines)

        with open(tscn_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(tscn_lines))
        count_2d += 1

    print(f"Generated {count_2d} PixelIsometric scenes in scenes/items/*/")

    # 2. Generate 2D scenes for Isometric RPG World Pack
    base_rpg = 'assets/isometric_rpg_world'
    rpg_pngs = glob.glob(f'{base_rpg}/**/*.png', recursive=True)
    
    rpg_cats = ["RPG_Buildings", "RPG_Props", "RPG_Nature", "RPG_Tiles"]
    for rc in rpg_cats:
        if rc not in registry["categories"]:
            registry["categories"].append(rc)
        registry["by_category"][rc] = []

    rpg_count = 0
    seen_names = set()
    for p in rpg_pngs:
        rel = os.path.relpath(p, base_rpg).replace('\\', '/')
        bname = os.path.splitext(os.path.basename(p))[0]
        bname_clean = sanitize_name(bname)

        lower_path = rel.lower()
        if any(k in lower_path for k in ['building', 'house', 'skyscrapers', 'city-hall', 'hospital', 'hotel', 'bakery', 'bank', 'police', 'school', 'shop', 'stadium', 'market']):
            subcat = "RPG_Buildings"
        elif any(k in lower_path for k in ['nature', 'tree', 'cliff', 'stone', 'hadge', 'hedge', 'fence']):
            subcat = "RPG_Nature"
        elif any(k in lower_path for k in ['til-isom', 'tiles_', 'tile']):
            subcat = "RPG_Tiles"
        else:
            subcat = "RPG_Props"

        unique_name = bname_clean
        idx = 1
        while unique_name in seen_names or unique_name in registry["items"]:
            unique_name = f"{bname_clean}_{idx}"
            idx += 1
        seen_names.add(unique_name)

        try:
            im = Image.open(p)
            w, h = im.size
            bbox = im.getbbox()
            if bbox:
                orig_x = (bbox[0] + bbox[2]) // 2
                orig_y = bbox[3] - 8
            else:
                orig_x, orig_y = w // 2, h - 8
        except Exception:
            w, h = 64, 64
            orig_x, orig_y = 32, 56

        fp_w = max(1, min(6, round(w / 48.0)))
        fp_h = fp_w

        tex_path = f"res://assets/isometric_rpg_world/{rel}"
        target_dir = os.path.join('scenes', 'items', 'RPG_World', subcat.replace('RPG_', ''))
        os.makedirs(target_dir, exist_ok=True)
        tscn_file = os.path.join(target_dir, f"{unique_name}.tscn")

        kind = "build" if subcat == "RPG_Buildings" else ("tile" if subcat == "RPG_Tiles" else "obj")
        item_data = {
            "name": unique_name,
            "display_name": unique_name.replace('_', ' '),
            "category": subcat,
            "kind": kind,
            "frames": 1,
            "directions": {
                "SE": {
                    "file": f"../../isometric_rpg_world/{rel}",
                    "origin": [orig_x, orig_y],
                    "footprint": [fp_w, fp_h],
                    "frame_width": w,
                    "frame_height": h
                }
            }
        }
        registry["items"][unique_name] = item_data
        registry["by_category"][subcat].append(unique_name)

        dirs_json = json.dumps(item_data["directions"])

        has_col = (kind in ["build", "obj"])
        col_lines = []
        if has_col:
            w_x = 16 * fp_w
            w_y = 8 * fp_w
            b_x = 16 * (fp_w - fp_h)
            b_y = 8 * (fp_w + fp_h)
            l_x = -16 * fp_h
            l_y = 8 * fp_h
            poly_str = f"PackedVector2Array(0, 0, {w_x}, {w_y}, {b_x}, {b_y}, {l_x}, {l_y})"
            col_lines = [
                '[node name="StaticBody2D" type="StaticBody2D" parent="."] ',
                '',
                '[node name="CollisionPolygon2D" type="CollisionPolygon2D" parent="StaticBody2D"] ',
                f'polygon = {poly_str}',
                ''
            ]

        tscn_lines = [
            '[gd_scene load_steps=3 format=3]',
            '',
            '[ext_resource type="Script" path="res://scripts/iso_object.gd" id="1_script"]',
            f'[ext_resource type="Texture2D" path="{tex_path}" id="2_tex"]',
            '',
            f'[node name="{unique_name}" type="Node2D"]',
            'y_sort_enabled = true',
            'script = ExtResource("1_script")',
            f'item_id = "{unique_name}"',
            f'category = "{subcat}"',
            f'kind = "{kind}"',
            'direction = "SE"',
            f'footprint = Vector2i({fp_w}, {fp_h})',
            f'origin_offset = Vector2({orig_x}, {orig_y})',
            'total_frames = 1',
            f'has_collision = {"true" if has_col else "false"}',
            f'directions_data = {dirs_json}',
            '',
            '[node name="Sprite2D" type="Sprite2D" parent="."] ',
            'texture = ExtResource("2_tex")',
            'centered = false',
            f'offset = Vector2({-orig_x}, {-orig_y})',
            ''
        ]
        tscn_lines.extend(col_lines)

        with open(tscn_file, 'w', encoding='utf-8') as f:
            f.write('\n'.join(tscn_lines))
        rpg_count += 1

    print(f"Generated {rpg_count} RPG World scenes in scenes/items/RPG_World/*/")

    # 3. Generate 3D scenes for HanX & Tinyworks with StaticBody3D collision
    pack_mapping = {
        'low-poly-city-pack-hanx-city-pack': 'City',
        'low-poly-construction-pack-hanx-construction-pack': 'Construction',
        'low-poly-gas-station-pack-hanx-gasstation-pack': 'GasStation',
        'low-poly-park-nature-pack-hanx-park-pack': 'Park',
        'low-poly-school-pack-hanx-school-pack': 'School',
        'low-poly-shop-market-pack-hanx-shop-pack': 'Shop',
        'low-poly-traffic-pack-hanx-traffic-pack': 'Traffic'
    }

    count_3d = 0
    for pdir, folder_name in pack_mapping.items():
        search_path = os.path.join('assets', 'hanx_lowpoly', pdir)
        glbs = glob.glob(f'{search_path}/**/*.glb', recursive=True)
        tdir = os.path.join('scenes', 'items_3d', f"HanX_{folder_name}")
        os.makedirs(tdir, exist_ok=True)
        for g in glbs:
            bname = os.path.splitext(os.path.basename(g))[0]
            if bname.startswith('_All'):
                continue
            clean_bname = sanitize_name(bname)
            rel_glb = os.path.relpath(g, '.').replace('\\', '/')
            tscn_file = os.path.join(tdir, f"{clean_bname}.tscn")
            content = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://{rel_glb}" id="1_model"]

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3(2, 2, 2)

[node name="{clean_bname}" type="StaticBody3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0)
shape = SubResource("BoxShape3D_1")
'''
            with open(tscn_file, 'w', encoding='utf-8') as f:
                f.write(content)
            count_3d += 1

    tiny_glbs = glob.glob('assets/tinyworks_fire_station/**/*.glb', recursive=True)
    tdir = os.path.join('scenes', 'items_3d', 'Fire_Station_PSX')
    os.makedirs(tdir, exist_ok=True)
    for g in tiny_glbs:
        bname = os.path.splitext(os.path.basename(g))[0]
        clean_bname = sanitize_name(bname)
        rel_glb = os.path.relpath(g, '.').replace('\\', '/')
        tscn_file = os.path.join(tdir, f"{clean_bname}.tscn")
        content = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://{rel_glb}" id="1_model"]

[sub_resource type="BoxShape3D" id="BoxShape3D_1"]
size = Vector3(1, 1, 1)

[node name="{clean_bname}" type="StaticBody3D"]

[node name="Model" parent="." instance=ExtResource("1_model")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.5, 0)
shape = SubResource("BoxShape3D_1")
'''
        with open(tscn_file, 'w', encoding='utf-8') as f:
            f.write(content)
        count_3d += 1

    print(f"Generated {count_3d} 3D scenes in scenes/items_3d/*/")

    # 4. Save Final Registry
    with open('resources/catalog/catalog_registry.json', 'w', encoding='utf-8') as f:
        json.dump(registry, f, indent=2)
    print(f"Saved catalog_registry.json ({len(registry['items'])} items, {len(registry['categories'])} categories).")

    # 5. TileSets
    city_tileset = '''[gd_resource type="TileSet" load_steps=5 format=3]

[ext_resource type="Texture2D" path="res://assets/pixel_isometric/Tilesets/City_Ground_Iso_Tileset_32x16.png" id="1_tex"]
[ext_resource type="Texture2D" path="res://assets/pixel_isometric/Tilesets/Animated_Tiles_32x16.png" id="2_anim_tex"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]
texture = ExtResource("1_tex")
texture_region_size = Vector2i(32, 16)
'''
    for y in range(6):
        for x in range(8):
            city_tileset += f'{x}:{y}/0 = 0\n'

    city_tileset += '''
[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_anim"]
texture = ExtResource("2_anim_tex")
texture_region_size = Vector2i(32, 16)
0:0/animation_columns = 4
0:0/animation_speed = 4.0
0:0/animation_frame_0/duration = 1.0
0:0/animation_frame_1/duration = 1.0
0:0/animation_frame_2/duration = 1.0
0:0/animation_frame_3/duration = 1.0
0:0/0 = 0
0:1/animation_columns = 4
0:1/animation_speed = 4.0
0:1/animation_frame_0/duration = 1.0
0:1/animation_frame_1/duration = 1.0
0:1/animation_frame_2/duration = 1.0
0:1/animation_frame_3/duration = 1.0
0:1/0 = 0

[resource]
tile_shape = 1
tile_layout = 5
tile_size = Vector2i(32, 16)
sources/0 = SubResource("TileSetAtlasSource_1")
sources/1 = SubResource("TileSetAtlasSource_anim")
'''
    with open('resources/tilesets/city_ground_tileset.tres', 'w', encoding='utf-8') as f:
        f.write(city_tileset)

    floors_tileset = '''[gd_resource type="TileSet" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://assets/pixel_isometric/Tilesets/Floors_Iso_Tileset_32x16.png" id="1_tex"]

[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"]
texture = ExtResource("1_tex")
texture_region_size = Vector2i(32, 16)
'''
    for y in range(4):
        for x in range(8):
            floors_tileset += f'{x}:{y}/0 = 0\n'

    floors_tileset += '''
[resource]
tile_shape = 1
tile_layout = 5
tile_size = Vector2i(32, 16)
sources/0 = SubResource("TileSetAtlasSource_1")
'''
    with open('resources/tilesets/floors_tileset.tres', 'w', encoding='utf-8') as f:
        f.write(floors_tileset)

    from audit_asset_alignment import audit
    audit(apply=True)
    print("Complete pipeline build successful!")

if __name__ == '__main__':
    main()
