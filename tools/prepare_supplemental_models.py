"""Prepare grounded, consistently sized GLB prefabs; prefer supplied low-poly editions."""
from pathlib import Path
import itertools
import json
import re
import shutil
import struct
import sys
import argparse
import numpy as np
from ingest_supplemental_assets import ROOT, RAW, REPORT, slug, digest
from prepare_supplemental_assets import Builder, human, res, write, REGISTRY
from model_previews import build_previews


def read_glb(path):
    with path.open('rb') as stream:
        magic, version, _ = struct.unpack('<III', stream.read(12))
        if magic != 0x46546c67 or version != 2:
            raise ValueError(f'Unsupported GLB: {path}')
        length, kind = struct.unpack('<II', stream.read(8))
        if kind != 0x4e4f534a:
            raise ValueError(f'Missing glTF JSON: {path}')
        return json.loads(stream.read(length))


def transform(node):
    if 'matrix' in node:
        return np.array(node['matrix'], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get('rotation', [0, 0, 0, 1])
    rotation = np.array([[1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)],
                         [2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)],
                         [2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)]])
    result = np.eye(4)
    result[:3, :3] = rotation @ np.diag(node.get('scale', [1, 1, 1]))
    result[:3, 3] = node.get('translation', [0, 0, 0])
    return result


def model_bounds(data):
    points = []
    def visit(index, parent):
        node = data['nodes'][index]; matrix = parent @ transform(node)
        if 'mesh' in node:
            for primitive in data['meshes'][node['mesh']]['primitives']:
                accessor = data['accessors'][primitive['attributes']['POSITION']]
                if 'min' not in accessor or 'max' not in accessor:
                    raise ValueError('A mesh has no authored POSITION bounds')
                for corner in itertools.product(*zip(accessor['min'], accessor['max'])):
                    points.append((matrix @ np.array([*corner, 1]))[:3])
        for child in node.get('children', []): visit(child, matrix)
    scene = data['scenes'][data.get('scene', 0)]
    for node in scene['nodes']: visit(node, np.eye(4))
    if not points:
        raise ValueError('GLB has no mesh geometry')
    return np.min(points, axis=0), np.max(points, axis=0)


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack', choices=['Arcade machines', 'Deciduous trees', 'Satellites', 'Spaceships', 'Spaceships II'], help='Only prepare this source pack display name')
    parser.add_argument('--previews-only', action='store_true', help='Keep geometry/registry untouched; rebuild model thumbnails')
    parser.add_argument('--no-render', action='store_true', help='Use supplied GIFs when a renderer is unavailable')
    parser.add_argument('--godot', help='Godot executable (otherwise GODOT_BIN or PATH)')
    parser.add_argument('--force', action='store_true', help='Ignore preview cache')
    args = parser.parse_args()
    builder = Builder(existing=True)
    def previews():
        selected = {ident: asset for ident, asset in builder.models.items()
                    if not args.pack or asset.get('data', {}).get('source_pack') == args.pack}
        if not selected:
            parser.error('No model assets match this pack')
        build_previews(selected, godot=args.godot, render=not args.no_render, force=args.force)
    if args.previews_only:
        previews()
        return
    calibration_path=ROOT/'resources/catalog/supplemental_model_bounds.json'
    calibrated=json.loads(calibration_path.read_text(encoding='utf-8')).get('bounds_by_sha256',{}) if calibration_path.exists() else {}
    definitions = [('3D_arcade_machines_pack_lowpoly', 'Arcade machines', 'Arcade', 'Furniture'),
                   ('3D_deciduous_trees_pack', 'Deciduous trees', 'Trees', 'Nature'),
                   ('3D_satellites_pack_low', 'Satellites', 'Satellites', 'Spacecraft'),
                   ('3D_spaceships_pack', 'Spaceships', 'Spaceships', 'Spacecraft'),
                   ('3D_spaceships_pack_2_low', 'Spaceships II', 'Spaceships_II', 'Spacecraft')]
    for source_name, pack, short, category in definitions:
        if args.pack and args.pack != pack: continue
        folder = RAW / source_name
        metadata = builder.notice(pack, folder, author='Polyy.AI' if source_name != '3D_spaceships_pack' else '',
                                  url='https://polyy.ai' if source_name != '3D_spaceships_pack' else '')
        target = ROOT / 'assets/supplemental_models' / slug(pack)
        target.mkdir(parents=True, exist_ok=True)
        notices = list(folder.rglob('LICENSE.txt'))
        if notices:
            write(target / 'LICENSE.txt', '\n\n'.join(p.read_text(encoding='utf-8', errors='replace') for p in notices))
        models = sorted(folder.rglob('*.glb'))
        for path in models:
            key = path.stem.removesuffix('_low'); name = re.sub(r'^\d+_(?:arcade_\d+_)?', '', key)
            if key.isdigit(): name = 'Spacecraft ' + key.zfill(2)
            name = re.sub(r'^tree_\d+_', '', name)
            source_hash=digest(path); data = read_glb(path)
            if source_hash in calibrated: low,high=np.array(calibrated[source_hash]['min']),np.array(calibrated[source_hash]['max'])
            else: low,high=model_bounds(data)
            size = high-low
            if category == 'Nature':
                height = 10 if 'birch' in key else 12 if 'oak' in key else 5 if 'blossom' in key else 8
                scale = height / size[1]
            elif category == 'Furniture':
                height = .7 if 'bartop' in key else 1.4 if 'motorcycle' in key else 1.5 if 'racer_' in key else 2.2 if 'dance' in key else 1.8
                scale = height / size[1]
            else:
                span = .35 if 'cubesat' in key else 7 if 'solar_sail' in key else 6 if 'station' in key else 3 if short == 'Satellites' else 6
                scale = span / max(size)
            scaled = size*scale; center = (low+high)*.5; offset = np.array([-center[0],-low[1],-center[2]])*scale
            active = target / (key + '.glb')
            if not active.exists() or digest(active) != digest(path): shutil.copyfile(path, active)
            scene = ROOT / 'scenes/items_3d' / ('Supplemental_' + short) / (key + '.tscn')
            preview_path = target / (key + '_preview.png')
            ident = '3d:Supplemental_' + short + '/' + key
            triangles = sum(data['accessors'][p['indices']]['count']//3 for mesh in data['meshes'] for p in mesh['primitives'] if 'indices' in p)
            behavior = {'layer': 'Nature' if category == 'Nature' else 'Furniture' if category == 'Furniture' else 'Decorations',
                        'building': False, 'door': False, 'vehicle': False, 'ground': False,
                        'collision': 'box' if category != 'Spacecraft' else 'none', 'walk': {'height': min(2.2,float(scaled[1]))}}
            builder.models[ident] = {'id':ident,'mode':'3d','name':human(name),'category':'Supplemental '+category,
                                    'path':res(scene),'behavior':behavior,
                                    'data':{**metadata,'source_pack':pack,'source_name':path.name,'source_files':[res(path)],
                                            'preview_path':res(preview_path),'source_hash':source_hash,'triangles':triangles,
                                            'quality':'Supplied low-poly edition' if ('low' in source_name) else 'Original mesh',
                                            'source_bounds':[low.tolist(),high.tolist()],'prepared_scale':float(scale),
                                            'model_file':res(active),'engine_calibrated':source_hash in calibrated,
                                            'target_dimension':'height' if category in ('Nature','Furniture') else 'span',
                                            'target_size':float(height if category in ('Nature','Furniture') else span),
                                            'default_scale':1.0}}
            alternatives={'3D_arcade_machines_pack_lowpoly':'3D_arcade_machines_pack',
                          '3D_satellites_pack_low':'3D_satellites_pack','3D_spaceships_pack_2_low':'3D_spaceships_pack_2'}
            variants=[{'file':res(path),'quality':'Active low-poly edition' if 'low' in source_name else 'Active original edition','sha256':source_hash}]
            if source_name in alternatives:
                full=next((RAW/alternatives[source_name]).rglob(key+'.glb'),None)
                if full: variants.append({'file':res(full),'quality':'Higher-detail original retained in source intake','sha256':digest(full)})
            builder.models[ident]['data']['source_variants']=variants
            # A tree's canopy is visual overhang; only its trunk blocks exploration and defines snapping contact.
            tree = category == 'Nature'; collidable = category != 'Spacecraft'
            footprint = [.7,float(scaled[1]),.7] if tree else scaled.tolist()
            shape = f'[sub_resource type="CylinderShape3D" id="CollisionShape"]\nheight = 2.0\nradius = 0.25' if tree else f'[sub_resource type="BoxShape3D" id="CollisionShape"]\nsize = Vector3({scaled[0]}, {scaled[1]}, {scaled[2]})'
            body = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path={json.dumps(res(active))} id="1"]

{shape}

[node name={json.dumps(slug(key))} type="StaticBody3D"]
collision_layer = {1 if collidable else 0}
collision_mask = 0
metadata/authored_footprint = [{-footprint[0]*.5}, 0.0, {-footprint[2]*.5}, {footprint[0]}, {footprint[1]}, {footprint[2]}]

[node name="Model" type="Node3D" parent="."]
position = Vector3({offset[0]}, {offset[1]}, {offset[2]})
scale = Vector3({scale}, {scale}, {scale})

[node name="Source" parent="Model" instance=ExtResource("1")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
position = Vector3(0, {1.0 if tree else scaled[1]*.5}, 0)
shape = SubResource("CollisionShape")
disabled = {'false' if collidable else 'true'}
'''
            write(scene, body)
        print(f'{pack}: {len(models)} grounded GLB prefabs', flush=True)
    builder.stats['model_assets'] = len(builder.models)
    builder.stats['alternative_model_sources']=sum(len(asset['data']['source_variants'])-1 for asset in builder.models.values())
    builder.save()
    previews()
    print(f'Prepared {len(builder.models)} model assets', flush=True)


if __name__ == '__main__': main()
