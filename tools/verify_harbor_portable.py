"""Import and exercise the two harbor exports in independent projects on F:."""
import json
import os
from pathlib import Path
import shutil
import uuid
from zipfile import ZipFile

from verify_collection_portable import stage
from verify_construction_costs_portable import run_import
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/verification/asset_expansion/N14"


def main():
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N14" / uuid.uuid4().hex
    records = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = OUT / f"harbor_{mode}.zip"
        package_hash = sha(package.read_bytes())
        with ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target) for name in names)
            assert not any(name.startswith((".godot/", "output/")) or name.endswith("harbor_tools.gd") for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            notice = "assets/BOAT/Read Me.txt"
            assert archive.read(notice) == (ROOT / notice).read_bytes()
            assert "assets/imported_prepared/animated/Added_animated_tireme_c8c74bbe_SE.png" in names
            assert "resources/previews_imported/Added_animated_tireme_c8c74bbe.png" in names
            assert "resources/previews_imported/Added_piers_pier_f248daea.png" in names
            assert not any("rodwan_water_ef4e19a5" in name or "Added_animated_boat_9ee9b341" in name for name in names)
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_harbor_export.gd", target / "verify_harbor.gd")
        # Windows Forward+ import teardown can fault after the cache is ready.
        # The Model export still runs under its packaged Forward+ renderer.
        command = run_import(engine, target, mode, windows_model_renderer="gl_compatibility")
        log = target / "verification_import.log"
        runs = [{"stage": "import", "command": command, "log": str(log), "sha256": sha(log.read_bytes())}]
        print(f"PASS: harbor {mode} import", flush=True)
        for label, flags in (
            ("runtime", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after",
                         "1600", "--script", "res://verify_harbor.gd"]),
            ("visible_main", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after", "40"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE HARBOR: 9 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert sha(package.read_bytes()) == package_hash
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: harbor {mode} {label}", flush=True)
        records.append({"mode": mode, "destination": str(target), "package_sha256": package_hash,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (OUT / "portable_projects.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
