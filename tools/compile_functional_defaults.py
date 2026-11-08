"""Compile the reviewed I01 overlay; never infer gameplay from filenames."""
from pathlib import Path
import argparse
import json
import math
from prepare_supplemental_assets import write

ROOT = Path(__file__).resolve().parents[1]


def reviewed_scene(ident, root):
    if ident.startswith("3d:"):
        return root / "scenes/items_3d" / (ident[3:] + ".tscn")
    if ident.startswith("2d:"):
        path = root / "resources/catalog/catalog_registry.json"
        registry = json.loads(path.read_text(encoding="utf-8")) if path.is_file() else {}
        item = registry.get("items", {}).get(ident[3:], {})
        if not item: return None
        category = item.get("category", "")
        scene = item.get("scene_path", "")
        if not scene:
            folder = "RPG_World/" + category[4:] if category.startswith("RPG_") else category.replace(" & ", "_").replace(" ", "_")
            scene = f"res://scenes/items/{folder}/{ident[3:]}.tscn"
        if scene.startswith("res://"): return root / scene[6:]
    return None


def valid_entrance(source, sprite):
    def point(value):
        return isinstance(value, dict) and all(
            isinstance(value.get(key), list) and len(value[key]) == (2 if sprite else 3)
            and all(type(n) in (int, float) and math.isfinite(n) and abs(n) <= 10000 for n in value[key])
            for key in ("point", "arrival"))
    anchor = source.get("entrance_anchor", {})
    return (source.get("building") is True and source.get("entrance") is True
            and isinstance(anchor, dict) and
            (isinstance(anchor.get("views"), dict) and bool(anchor["views"]) and all(point(v) for v in anchor["views"].values()) if sprite else point(anchor)))


def compile_defaults(root=ROOT, check=False):
    catalog = root / "resources/catalog"
    overlay = json.loads((catalog / "functional_defaults.json").read_text(encoding="utf-8"))
    if overlay.get("version") != 1 or overlay.get("revision") != 1:
        raise ValueError("Unsupported functional-default revision")
    businesses = json.loads((catalog / "businesses.json").read_text(encoding="utf-8"))
    roles = json.loads((catalog / "citizen_roles.json").read_text(encoding="utf-8"))
    behavior = json.loads((catalog / "asset_behaviors.json").read_text(encoding="utf-8"))
    changed = False
    for ident, config in sorted(overlay["assets"].items()):
        scene = reviewed_scene(ident, root)
        if scene is None or not scene.is_file():
            raise ValueError(f"Unknown reviewed asset: {ident}")
        if config.get("business") not in ("cafe", "shop", "service") or config.get("citizen_role") != "shop":
            raise ValueError(f"Unsupported reviewed behavior: {ident}")
        source = behavior.get(ident, {})
        if not valid_entrance(source, ident.startswith("2d:")):
            raise ValueError(f"Review this building's entrance before assigning gameplay: {ident}")
        changed |= businesses.get(ident) != config["business"] or roles.get(ident) != config["citizen_role"]
        businesses[ident] = config["business"]; roles[ident] = config["citizen_role"]
    if check:
        if changed: raise ValueError("Compiled defaults are stale; run tools/compile_functional_defaults.py")
    else:
        for name, data in (("businesses.json", businesses), ("citizen_roles.json", roles)):
            write(catalog / name, json.dumps(data, ensure_ascii=False, indent=2))
    print(f"Functional defaults: {len(overlay['assets'])} reviewed buildings; {'checked' if check else 'compiled'}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    compile_defaults(check=parser.parse_args().check)
