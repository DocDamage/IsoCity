"""Verify both rendering fixtures in isolated portable projects."""
import argparse
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_construction_costs_portable import run_import
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/I19"
SHIP = "3d:Supplemental_Spaceships_II/hammerhead_cruiser"
ARCADE = "3d:Supplemental_Arcade/13_arcade_13_racer_blue"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prepare", action="store_true", help="Prepare fresh packages in a separate release directory")
    args = parser.parse_args()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable")
    out = OUT
    if args.prepare:
        out = OUT.parent / "P7" / "rendering_budget" / uuid.uuid4().hex
        out.mkdir(parents=True)
        stage([engine, "--path", str(ROOT), "--resolution", "1480x900", "--disable-vsync",
               "--audio-driver", "Dummy", "--quit-after", "5000", "--script", "res://tools/test_rendering_budget.gd",
               "--", "--consumer-ui", "--portable", "--rendering-output", "res://" + out.relative_to(ROOT).as_posix()],
              out, "rendering_fixtures", 180)
    dest = ROOT.parent / "IsoCity-portable-validation" / "I19" / uuid.uuid4().hex
    info = []
    for mode in ("2d", "3d"):
        target = dest / mode
        target.mkdir(parents=True)
        package = out / f"rendering_{mode}.zip"
        package_hash = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            catalog_path = "resources/catalog/rendering_budget.json"
            assert archive.read(catalog_path) == (ROOT / catalog_path).read_bytes()
            catalog = json.loads(archive.read(catalog_path))
            for id in (SHIP, ARCADE):
                for edition in ("low", "full"):
                    variant = catalog["assets"][id][edition]
                    path = variant["path"].removeprefix("res://")
                    assert sha(archive.read(path)) == variant["sha256"]
                    assert path + ".import" in names
            assert sum("/full_detail/" in name and name.endswith(".glb") for name in names) == 2
            assert "assets/supplemental_models/Spaceships_II/LICENSE.txt" in names
            assert "assets/supplemental_models/Arcade_machines/LICENSE.txt" in names
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_rendering_export.gd", target / "verify_rendering.gd")
        command = run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
        log = target / "verification_import.log"
        runs = [{"stage": "import", "command": command, "log": str(log), "sha256": sha(log.read_bytes())}]
        print(f"PASS: rendering {mode} import", flush=True)
        for label, flags in (
            ("runtime", ["--resolution", "1480x900", "--disable-vsync", "--audio-driver", "Dummy", "--quit-after",
                         "2400", "--script", "res://verify_rendering.gd"]),
            ("visible_main", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after", "40"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE RENDERING: 5 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert sha(package.read_bytes()) == package_hash
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: rendering {mode} {label}", flush=True)
        info.append({"mode": mode, "destination": str(target), "package_sha256": package_hash,
                     "manifest_files_verified": len(manifest["files"]), "results": runs})
    report = (out if args.prepare else dest) / "portable_projects.json"
    report.write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    print(f"Rendering verification report: {report}")


if __name__ == "__main__":
    main()
