"""Verify pending and completed assembly packages outside the source checkout."""
import argparse
from pathlib import Path
import hashlib
import json
import os
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/I20/verified"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", nargs="?", type=Path, default=OUT)
    packages = parser.parse_args().packages.resolve()
    engine = os.environ["GODOT_BIN"]
    destination = Path(r"F:\dev\IsoCity-portable-validation\I20") / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        with zipfile.ZipFile(packages / f"assembly_built_{mode}.zip") as built:
            expected = json.loads(built.read("city-source.json"))["documents"][mode]
        for state in ("pending", "built"):
            target = destination / f"{state}_{mode}"
            target.mkdir(parents=True)
            package = packages / f"assembly_{state}_{mode}.zip"
            package_sha = sha(package)
            with zipfile.ZipFile(package) as archive:
                names = archive.namelist()
                assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
                assert not any(".godot/" in name or name.startswith("output/") for name in names)
                for entry in json.loads(archive.read("export-manifest.json"))["files"]:
                    data = archive.read(entry["path"])
                    assert len(data) == entry["bytes"]
                    assert hashlib.sha256(data).hexdigest() == entry["sha256"], entry["path"]
                for name in ("scripts/builder/functional_assembly_plan.gd", "scripts/builder/blueprint_plan.gd"):
                    assert hashlib.sha256(archive.read(name)).hexdigest() == sha(ROOT / name)
                source = json.loads(archive.read("city-source.json"))["documents"][mode]
                assert bool(source.get("blueprints")) == (state == "pending")
                if state == "pending":
                    assert "3d:HanX_School/Teacher_Desk" not in json.dumps(source["objects"])
                    assert "3d:HanX_School/Teacher_Desk" in json.dumps(source["blueprints"])
                assert "scenes/items_3d/HanX_School/Teacher_Desk.tscn" in names
                assert "resources/previews_3d/HanX_School/Teacher_Desk.png" in names
                archive.extractall(target)
            assert not (target / ".godot").exists()
            (target / "expected_assembly.json").write_text(json.dumps(expected), encoding="utf-8")
            shutil.copyfile(ROOT / "tools/test_functional_assembly_export.gd", target / "verify_assembly.gd")
            project = target / "project.godot"
            original = settings(project.read_bytes())
            for label, args in (
                ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
                ("runtime", ["--headless", "--fixed-fps", "60", "--script", "res://verify_assembly.gd"]),
                ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
            ):
                stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *args], target, label, 180)
                assert settings(project.read_bytes()) == original and sha(package) == package_sha
                log = target / f"verification_{label}.log"
                results.append({"package": package.name, "stage": label, "log": str(log), "sha256": sha(log), "package_sha256": package_sha})
                print(f"PASS: {state} {mode} {label}", flush=True)
    (packages / "portable_projects.json").write_text(json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
