"""Open fleet exports from fresh projects outside the working checkout."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_construction_costs_portable import run_import

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "I11" / uuid.uuid4().hex
    results = []
    assert not (packages / "restricted.zip").exists()
    for mode in ("2d", "3d"):
        package = packages / f"fleet_{mode}.zip"
        target = destination / mode
        target.mkdir(parents=True)
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(".godot/" in name or name.startswith("output/") for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for item in manifest["files"]:
                data = archive.read(item["path"])
                assert len(data) == item["bytes"] and sha(data) == item["sha256"], item["path"]
            for name in ("resources/catalog/fleet.json", "scripts/builder/fleet_plan.gd",
                         "scripts/builder/traffic_runtime.gd", "scripts/builder/transit_runtime.gd",
                         "scripts/builder/service_runtime.gd", "scripts/builder/service_plan.gd"):
                assert sha(archive.read(name)) == sha((ROOT / name).read_bytes()), name
            world = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert world["traffic"]["population"] == 1 and not world.get("transit", {}).get("enabled")
            chosen = {entry["asset"] for entries in world["fleet"].values() for entry in entries}
            assert len(chosen) == 4 and chosen.issubset(manifest["assets"])
            assert any(entry["weight"] == 0 for entry in world["fleet"]["traffic"])
            assert all("Flipped_Fleet_EU" not in name for name in names)
            if mode == "3d":
                for id in chosen:
                    path = id.removeprefix("3d:")
                    assert f"scenes/items_3d/{path}.tscn" in names
                    assert f"resources/previews_3d/{path}.png" in names
            else:
                for id in chosen:
                    path = id.removeprefix("2d:")
                    assert f"scenes/items/Vehicles/{path}.tscn" in names
                    assert f"assets/pixel_isometric/Sprites/Vehicles/{path}_SE.png" in names
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_fleet_export_runtime.gd", target / "verify_fleet.gd")
        project = target / "project.godot"
        initial_settings = settings(project.read_bytes())
        for label, flags in (
            ("import", []),
            ("runtime", ["--headless", "--fixed-fps", "60", "--script", "res://verify_fleet.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            if label == "import":
                run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
            else:
                stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            assert settings(project.read_bytes()) == initial_settings and sha(package.read_bytes()) == digest
            log = target / f"verification_{label}.log"
            results.append({"package": str(package), "stage": label, "log": str(log),
                            "sha256": sha(log.read_bytes()), "package_sha256": digest})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
