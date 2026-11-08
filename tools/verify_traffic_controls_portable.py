"""Import and run authored signal fixtures independently on F:."""
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
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ["GODOT_BIN"]
    destination = Path(r"F:\dev\IsoCity-portable-validation\I10") / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"signals_{mode}.zip"
        target = destination / mode
        target.mkdir(parents=True)
        sha = digest(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(".godot/" in name or name.startswith("output/") for name in names)
            for entry in json.loads(archive.read("export-manifest.json"))["files"]:
                data = archive.read(entry["path"])
                assert len(data) == entry["bytes"] and digest(data) == entry["sha256"], entry["path"]
            for path in ("resources/catalog/traffic_controls.json", "scripts/builder/traffic_control_plan.gd",
                         "scripts/builder/traffic_junctions.gd", "scripts/builder/traffic_signal_views.gd"):
                assert digest(archive.read(path)) == digest((ROOT / path).read_bytes()), path
            if mode == "3d":
                for color in ("Red", "Amber", "Green"):
                    assert f"scenes/items_3d/HanX_Traffic/Traffic_Light_{color}.tscn" in names
                    assert f"resources/previews_3d/HanX_Traffic/Traffic_Light_{color}.png" in names
                    assert any(name.endswith(f"/GLB/Traffic_Light_{color}.glb") for name in names)
            else:
                assert "assets/pixel_isometric/Sprites/Street_Props/Traffic_Light_SE.png" in names
            data = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert all(item["traffic_control"]["timing"] == {"green": 4, "walk": 3, "clear": 2} for item in data["objects"])
            assert not data.get("traffic", {}).get("enabled", False)
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_traffic_control_export.gd", target / "verify_signals.gd")
        project = target / "project.godot"
        original_settings = settings(project.read_bytes())
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--script", "res://verify_signals.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            assert settings(project.read_bytes()) == original_settings and digest(package.read_bytes()) == sha
            log = target / f"verification_{label}.log"
            results.append({"package": str(package), "stage": label, "log": str(log),
                            "sha256": digest(log.read_bytes()), "package_sha256": sha})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
