"""Prepare reviewed higher-detail visual editions without changing canonical assets."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import shutil

import numpy as np

from prepare_supplemental_models import read_glb, model_bounds

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "resources/catalog/rendering_budget.json"
SOURCE = ROOT / "resources/catalog/supplemental_registry.json"


def file_for(resource):
    path = (ROOT / resource.removeprefix("res://")).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError(resource)
    return path


def digest(path):
    return sha256(path.read_bytes()).hexdigest()


def metrics(data):
    primitives = [p for mesh in data["meshes"] for p in mesh["primitives"] if p.get("mode", 4) == 4]
    return {
        "triangles": sum(data["accessors"][p.get("indices", p["attributes"]["POSITION"])]["count"] // 3
                         for p in primitives),
        "materials": len(data.get("materials", [])),
        "images": len(data.get("images", [])),
    }


def build(check):
    models = json.loads(SOURCE.read_text(encoding="utf-8"))["models"]
    result = {"version": 1, "assets": {}}
    for asset_id, asset in sorted(models.items()):
        data = asset["data"]
        variants = data.get("source_variants", [])
        if len(variants) != 2 or not data.get("source_export_allowed", False):
            continue
        low, full = variants
        low_path, full_path = (file_for(row["file"]) for row in variants)
        active = file_for(data["model_file"])
        assert digest(low_path) == digest(active) == low["sha256"], asset_id
        assert digest(full_path) == full["sha256"], asset_id
        low_data, full_data = read_glb(low_path), read_glb(full_path)
        for edition in (low_data, full_data):
            assert not edition.get("skins") and not edition.get("animations"), asset_id
            assert all(m.get("alphaMode", "OPAQUE") == "OPAQUE" for m in edition.get("materials", [])), asset_id
        lower, upper = model_bounds(full_data)
        canonical_min, canonical_max = np.asarray(data["source_bounds"])
        canonical_size = (canonical_max - canonical_min) * data["prepared_scale"]
        full_size = upper - lower
        axis = 1 if data["target_dimension"] == "height" else int(np.argmax(canonical_size))
        scale = float(canonical_size[axis] / full_size[axis])
        error = float(np.max(np.abs(canonical_size - full_size * scale)) / max(canonical_size))
        assert error <= .06, (asset_id, error)
        center = (lower + upper) / 2
        offset = np.array([-center[0], -lower[1], -center[2]]) * scale
        target = active.parent / "full_detail" / active.name
        if not target.exists() or digest(target) != full["sha256"]:
            if check:
                raise RuntimeError(f"Missing or stale prepared variant {target}")
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_suffix(".glb.tmp")
            shutil.copyfile(full_path, tmp)
            assert digest(tmp) == full["sha256"], asset_id
            tmp.replace(target)
        low_cost, full_cost = metrics(low_data), metrics(full_data)
        assert low_cost["triangles"] < full_cost["triangles"], asset_id
        result["assets"][asset_id] = {
            "regular": "low", "photo": "full",
            "low": {"path": data["model_file"], "sha256": low["sha256"], **low_cost},
            "full": {"path": "res://" + target.relative_to(ROOT).as_posix(), "sha256": full["sha256"], **full_cost},
            "photo_offset": offset.tolist(), "photo_scale": scale,
            "span_difference": round(error, 6),
        }
    payload = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if check:
        assert CATALOG.read_text(encoding="utf-8") == payload
    else:
        CATALOG.write_text(payload, encoding="utf-8")
    print(f"Verified {len(result['assets'])} static low/full presentation pairs.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Check hashes and metadata without writing files")
    build(parser.parse_args().check)
