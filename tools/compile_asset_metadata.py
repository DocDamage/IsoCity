"""Compile reviewed appearance families and animation evidence, preserving IDs."""
from pathlib import Path
import argparse
import hashlib
import json
import re
from prepare_supplemental_assets import write
from prepare_supplemental_models import read_glb

ROOT = Path(__file__).resolve().parents[1]
PACKS = {"Village buildings": "village", "Water towers": "water_towers", "Bonsai trees": "bonsai"}
PALETTE = re.compile(r"_(16-?bit(?:_dither)?|24bit|nopalette|voyager(?:_dither)?)$")
LOCOMOTION = {
    'Characters · Directional girl': ('iddle_001', 'anim_walkwhd', 'runhd_001'),
    'Characters · Businessman': ('idle', 'walk', 'running'),
    'Characters · Blue robot': ('idleaim', 'walkingshoot', None),
    'Characters · Robot': ('idleaim', 'walkingshoot', None),
    'Characters · Red robot': ('idleaim', 'walkingshoot', None),
    'Characters · Great sword knight': ('2hidle5', '2hwalk', None),
    'Characters · Orange shirt girl': ('readyidle', 'walk', 'run'),
    'Characters · Boxer': ('idle1', 'walkfoward', 'runforward'),
    'Characters · Eldrin Vaelor': ('idle', 'revision_walk', None),
}
POSED_MODELS = {
    '3d:Supplemental_SWAT/SWAT_K9_Dog_Sit',
    '3d:Supplemental_SWAT/SWAT_K9_Dog_Stand',
    '3d:Supplemental_SWAT/SWAT_Pose_Breacher_Ram',
    '3d:Supplemental_SWAT/SWAT_Pose_Hand_Signal',
    '3d:Supplemental_SWAT/SWAT_Pose_Kneel_Aim',
    '3d:Supplemental_SWAT/SWAT_Pose_Pistol_Aim',
    '3d:Supplemental_SWAT/SWAT_Pose_Radio',
    '3d:Supplemental_SWAT/SWAT_Pose_Rifle_Aim',
    '3d:Supplemental_SWAT/SWAT_Pose_Rifle_Ready',
    '3d:Supplemental_SWAT/SWAT_Pose_Shield_Pistol',
    '3d:Supplemental_SWAT/SWAT_Pose_Sniper_Prone',
}


def runtime_actions(item):
    clips = item.get('animations', {})
    if item.get('kind') != 'char': return {}
    if clips:
        choices = LOCOMOTION.get(item.get('source_pack'))
        if not choices: return {}
        result = {}
        for semantic, selected in zip(('idle', 'walk', 'run'), choices):
            fallback = selected is None
            selected = choices[1] if fallback else selected
            if selected not in clips or not clips[selected].get('directions'):
                raise ValueError(f"Missing reviewed {semantic} clip: {item.get('source_pack')}/{selected}")
            clip = clips[selected]
            result[semantic] = {'clip': selected, 'loop': any(view.get('frames', 1) > 1 for view in clip['directions'].values()),
                                'directions': sorted(clip['directions']), 'pose': 'standing' if semantic == 'idle' else 'moving'}
            if fallback: result[semantic]['fallback'] = 'walk'
        return result
    if int(item.get('frames', 1)) >= 9:
        return {'idle': {'first_frame': 0, 'frame_count': 2, 'fps': 1.0, 'loop': True},
                'walk': {'first_frame': 2, 'frame_count': 4, 'fps': 6.25, 'loop': True},
                'run': {'first_frame': 2, 'frame_count': 4, 'fps': 6.25, 'loop': True, 'fallback': 'walk'},
                'sit': {'first_frame': 6, 'frame_count': 1, 'fps': 1.0, 'loop': False},
                'wave': {'first_frame': 7, 'frame_count': 2, 'fps': 4.0, 'loop': True}}
    return {}


def family_metadata(item):
    pack = item.get("source_pack")
    if pack not in PACKS: return {}
    name, lighting = item["source_name"].rsplit("/", 1)
    match = PALETTE.search(name)
    if not match or lighting not in ("flat", "studio", "sun"):
        raise ValueError(f"Unreviewed appearance format: {pack}/{item['source_name']}")
    design = name[:match.start()]
    palette = match.group(1).replace("16-bit", "16bit")
    return {"family_id": "supplemental/" + PACKS[pack] + "/" + design,
            "family_name": design.replace("_", " ").capitalize(),
            "palette_id": palette, "lighting_id": lighting,
            "appearance_group": PACKS[pack]}


def sprite_status(item):
    views = item.get("directions", {})
    count = max([int(view.get("frames", item.get("frames", 1))) for view in views.values()] or [1])
    if item.get('source_view_kind') == 'state':
        return {'animation_status': 'static_sprite', 'animation_note': 'Supplied opening states; not facing or movement animation'}
    if item.get("kind") == "build" and count == 2:
        return {"animation_status": "directional_sprite", "animation_note": "Supplied day/night states; not movement animation"}
    if count > 1 or item.get("animations"):
        return {"animation_status": "animated_sprite"}
    return {"animation_status": "directional_sprite" if len(views) > 1 else "static_sprite"}


def mesh_status(paths):
    rigged, clips = False, []
    for path in sorted(set(paths)):
        data = read_glb(path) if path.suffix.casefold() == ".glb" else json.loads(path.read_text(encoding="utf-8"))
        rigged |= bool(data.get("skins"))
        clips.extend(animation.get("name", "Clip " + str(index + 1)) for index, animation in enumerate(data.get("animations", [])))
    return {"animation_status": "animated_mesh" if clips else "rigged_without_clips" if rigged else "static_mesh",
            "supplied_clips": sorted(set(clips))}


def apply_reviewed_names(root, assets, sources):
    path = root / 'resources/catalog/reviewed_names.json'
    if not path.exists(): return assets
    manifest = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(manifest, dict) or type(manifest.get('version')) is not int or manifest['version'] != 1 or not isinstance(manifest.get('assets'), dict):
        raise ValueError('Unsupported reviewed-name manifest')
    updates = {}
    hashes = {}
    for ident, entry in manifest['assets'].items():
        if ident not in assets or ident not in sources:
            raise ValueError('Reviewed name points to an unknown source: ' + ident)
        if not isinstance(entry, dict): raise ValueError('Invalid reviewed-name entry: ' + ident)
        source = sources[ident]
        if any(entry.get(key) != source.get(key) for key in ('source_name', 'source_pack')):
            raise ValueError('Reviewed name provenance changed: ' + ident)
        name, aliases = entry.get('display_name'), entry.get('aliases')
        if not isinstance(name, str) or not name.strip() or len(name) > 160 or any(ord(c) < 32 for c in name):
            raise ValueError('Invalid reviewed display name: ' + ident)
        if not isinstance(aliases, list) or len(aliases) > 24 or any(not isinstance(a, str) or not a.strip() or len(a) > 160 or any(ord(c) < 32 for c in a) for a in aliases):
            raise ValueError('Invalid reviewed aliases: ' + ident)
        if len({a.casefold() for a in aliases}) != len(aliases):
            raise ValueError('Duplicate reviewed aliases: ' + ident)
        if not isinstance(entry.get('review_note'), str) or not entry['review_note'].strip():
            raise ValueError('Reviewed name lacks visual evidence: ' + ident)
        art = entry.get('art_sha256')
        if not isinstance(art, dict) or not art: raise ValueError('Reviewed name lacks source art hashes: ' + ident)
        expected_paths = set()
        for view in source.get('directions', {}).values():
            relative = view['file']
            relative = 'assets/' + relative.removeprefix('../../') if relative.startswith('../../') else 'assets/pixel_isometric/' + relative
            expected_paths.add(relative)
        if set(art) != expected_paths: raise ValueError('Reviewed name source views changed: ' + ident)
        for relative, digest in art.items():
            file = (root / relative).resolve()
            if not file.is_relative_to((root / 'assets').resolve()): raise ValueError('Unsafe reviewed-name artwork path')
            if relative not in hashes: hashes[relative] = hashlib.sha256(file.read_bytes()).hexdigest()
            if hashes[relative] != digest: raise ValueError('Reviewed name artwork changed: ' + ident)
        updates[ident] = {'display_name': name, 'aliases': aliases, 'name_key': 'asset.' + ident}
        if not source.get('source_name'):
            # Older native imports have no source_name. Describe their actual
            # supplied file paths without changing pack/filter identity.
            updates[ident]['name_source'] = ' | '.join('res://' + relative for relative in sorted(expected_paths))
    for ident, metadata in updates.items(): assets[ident].update(metadata)
    return assets


def compile_metadata(root=ROOT, check=False):
    catalog = root / "resources/catalog"
    assets = {}
    sources = {}
    legacy_content = {}
    for filename in ("catalog_registry.json", "imported_registry.json", "supplemental_registry.json", "swat_registry.json", "reviewed_registry.json"):
        path = catalog / filename
        if not path.is_file(): continue
        raw = json.loads(path.read_text(encoding="utf-8"))
        legacy_content.update(raw.get('legacy_content', {}))
        for ident, item in raw.get("items", {}).items():
            sources['2d:' + ident] = item
            assets["2d:" + ident] = {**sprite_status(item), **family_metadata(item)}
            actions = runtime_actions(item)
            if actions: assets["2d:" + ident]['runtime_actions'] = actions
            for key in ('content_kind', 'source_view_kind', 'content_note', 'replacement_ids'):
                if key in item: assets['2d:' + ident][key] = item[key]
    for ident, metadata in legacy_content.items():
        if ident not in assets: raise ValueError('Reviewed content points to an unknown asset: ' + ident)
        assets[ident].update(metadata)
    # Inspect actual prepared model sources; a folder or filename saying
    # 'animated' is never evidence of clips. Repeated sources are read once.
    statuses = {}
    for scene in sorted((root / "scenes/items_3d").glob("*/*.tscn")):
        model_sources = [root / value.removeprefix("res://") for value in re.findall(r'path="(res://[^"\r\n]+\.(?:glb|gltf))"', scene.read_text(encoding="utf-8"), flags=re.I)]
        if not model_sources: continue
        signature = tuple(model_sources)
        if signature not in statuses: statuses[signature] = mesh_status(model_sources)
        ident = "3d:" + scene.relative_to(root / "scenes/items_3d").with_suffix("").as_posix()
        assets[ident] = dict(statuses[signature])
        if ident in POSED_MODELS and assets[ident]['animation_status'] == 'static_mesh': assets[ident]['animation_status'] = 'posed_mesh'
    assets = apply_reviewed_names(root, assets, sources)
    result = {"version": 1, "assets": dict(sorted(assets.items()))}
    if (catalog / 'asset_semantics.json').exists():
        from validate_asset_semantics import validate_semantics
        validate_semantics(root, assets)
    destination = catalog / "asset_metadata.json"
    content = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if (catalog / 'asset_themes.json').exists():
        from compile_asset_themes import compile_themes
        compile_themes(root, check=check)
    if (catalog / 'asset_style_rules.json').exists():
        from compile_asset_styles import compile_styles
        compile_styles(root, check=check)
    if check:
        if not destination.exists() or destination.read_text(encoding="utf-8") != content:
            raise ValueError("Asset metadata is stale; run tools/compile_asset_metadata.py")
    else: write(destination, content)
    families = {item["family_id"] for item in assets.values() if "family_id" in item}
    print(f"Asset metadata: {len(assets)} assets, {len(families)} reviewed families; {'checked' if check else 'compiled'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument("--check", action="store_true")
    compile_metadata(check=parser.parse_args().check)
