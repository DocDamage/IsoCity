"""I05 real-render regression: changed source materials must refresh imports."""
from pathlib import Path
import json
import shutil
import tempfile
from PIL import Image
import model_previews as previews


def dominant(path):
    with Image.open(path) as image:
        rgba = image.convert('RGBA')
        colors = rgba.get_flattened_data() if hasattr(rgba, 'get_flattened_data') else rgba.getdata()
        pixels = [color for color in colors if color[3] > 128]
    return [sum(color[index] for color in pixels) / len(pixels) for index in range(3)]


def main():
    out = previews.ROOT / 'output/verification/asset_expansion/I05'
    with tempfile.TemporaryDirectory(prefix='reimport-', dir=out) as folder:
        root = Path(folder)
        for name in ['tools', 'scripts/builder', 'assets/editor']: (root / name).mkdir(parents=True)
        for name in ['tools/model_previews.py', 'tools/render_builder_previews.gd', 'scripts/model_bounds.gd', 'scripts/builder/model_preview.gd', 'assets/editor/missing_object.png']:
            shutil.copyfile(previews.ROOT / name, root / name)
        (root / 'project.godot').write_text('config_version=5\n[application]\nconfig/name="I05 import verification"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n', encoding='utf-8')
        model = json.loads((previews.ROOT / 'tools/fixtures/asset_expansion/animated_triangle.gltf').read_text(encoding='utf-8'))
        model.pop('animations', None)
        model['materials'] = [{'pbrMetallicRoughness': {'baseColorFactor': [.9, .03, .03, 1], 'metallicFactor': 0, 'roughnessFactor': 1}}]
        model['meshes'][0]['primitives'][0]['material'] = 0
        source = root / 'model.gltf'; source.write_text(json.dumps(model), encoding='utf-8')
        (root / 'scene.tscn').write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://model.gltf" id="1"]\n[node name="Model" type="Node3D"]\n[node name="Source" parent="." instance=ExtResource("1")]\n', encoding='utf-8')
        assets = {'fixture': {'path': 'res://scene.tscn', 'data': {'model_file': 'res://model.gltf', 'preview_path': 'res://preview.png', 'source_files': []}}}
        assert previews.build_previews(assets, root=root) == {'fixture': 'render'}
        first = dominant(root / 'preview.png'); assert first[0] > first[2] * 2, first
        model['materials'][0]['pbrMetallicRoughness']['baseColorFactor'] = [.03, .03, .9, 1]
        source.write_text(json.dumps(model), encoding='utf-8')
        assert previews.build_previews(assets, root=root) == {'fixture': 'render'}
        second = dominant(root / 'preview.png'); assert second[2] > second[0] * 2, second
        assert previews.build_previews(assets, root=root) == {'fixture': 'cached'}
        result = {'red_source_mean_rgb': first, 'blue_source_mean_rgb': second, 'unchanged_run': 'cached', 'result': 'passed'}
        (out / 'reimport_verification.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        for name in ['preview_import.log', 'render.log']:
            shutil.copyfile(root / 'output/verification/asset_expansion/I05' / name, out / ('fixture_' + name))
        print('PASS: changed material was reimported and rendered blue; unchanged run reused the cache')


if __name__ == '__main__': main()
