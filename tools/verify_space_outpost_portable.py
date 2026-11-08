"""Verify both outpost exports as independent Godot projects."""
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
OUT = ROOT / "output/verification/asset_expansion/N20"
CATALOG = "resources/catalog/space_outpost.json"


def main():
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N20" / uuid.uuid4().hex
    records = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = OUT / f"outpost_{mode}.zip"
        checksum = sha(package.read_bytes())
        with ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target) for name in names)
            assert not any(name.startswith((".godot/", "output/")) or name.endswith("space_outpost_tools.gd") for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            assert archive.read(CATALOG) == (ROOT / CATALOG).read_bytes()
            catalog = json.loads(archive.read(CATALOG))
            required = {catalog[key] for key in ("habitat", "dock", "cargo", "satellite")}
            required.update(ship["asset"] for ship in catalog["ships"])
            assert required <= set(manifest["assets"])
            for name in ("container_freighter_preview.png", "bulk_hauler_preview.png", "03_cubesat_3u_preview.png"):
                assert any(path.endswith("/" + name) for path in names), name
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_space_outpost_export.gd", target / "verify_outpost.gd")
        command = run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
        log = target / "verification_import.log"
        runs = [{"stage": "import", "command": command, "log": str(log), "sha256": sha(log.read_bytes())}]
        print(f"PASS: outpost {mode} import", flush=True)
        for label, flags in (
            ("runtime", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after",
                         "1600", "--script", "res://verify_outpost.gd"]),
            ("visible_main", ["--disable-vsync", "--audio-driver", "Dummy", "--quit-after", "40"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                contents = log.read_text(encoding="utf-8")
                assert "PORTABLE SPACE OUTPOST: 9 checks, 0 failures" in contents
                assert ("Vulkan" in contents) == (mode == "3d")
            assert sha(package.read_bytes()) == checksum
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: outpost {mode} {label}", flush=True)
        records.append({"mode": mode, "destination": str(target), "package_sha256": checksum,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (OUT / "portable_projects.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
