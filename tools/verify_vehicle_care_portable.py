"""Verify vehicle care in freshly relocated Godot projects."""
import argparse
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]


def inspect_package(package, target, mode):
    with zipfile.ZipFile(package) as archive:
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in archive.namelist())
        assert not any(name.startswith((".godot/", "output/")) for name in archive.namelist())
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            data = archive.read(entry["path"])
            assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
        required = [
            "resources/catalog/vehicle_services.json",
            *(f"scripts/builder/vehicle_service_{name}.gd" for name in ("plan", "runtime", "view")),
            *(f"resources/previews_3d/HanX_GasStation/{name}.png" for name in ("Fuel_Pump", "Car_Wash", "Repair_Garage")),
            "assets/pixel_isometric/Sprites/Street_Props/EV_Charger_SE.png" if mode == "2d"
            else "resources/previews_3d/HanX_GasStation/EV_Charger.png",
        ]
        for name in required:
            assert sha(archive.read(name)) == sha((ROOT / name).read_bytes()), name
        van = "2d:Delivery_Van" if mode == "2d" else "3d:HanX_Traffic/Van_Delivery"
        assert van in manifest["assets"]
        source = json.loads(archive.read("city-source.json"))["documents"][mode]
        bays = [item for item in source["objects"] if item.get("vehicle_bay", {}).get("enabled")]
        cars = [item for item in source["objects"] if item.get("vehicle_care", {}).get("enabled")]
        assert {item["uid"] for item in bays} == {"fuel", "charge", "wash", "repair"}
        assert len(cars) == 5 and source["economy_account"]["cash"] == 1000
        archive.extractall(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    packages = parser.parse_args().packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N02" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"care_{mode}.zip"
        target = destination / mode
        target.mkdir(parents=True)
        digest = sha(package.read_bytes())
        inspect_package(package, target, mode)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_vehicle_care_export.gd", target / "verify_vehicle_care.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "18000", "--script", "res://verify_vehicle_care.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE VEHICLE CARE: 7 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "stage": label, "log": str(log),
                            "sha256": sha(log.read_bytes()), "package_sha256": digest})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
