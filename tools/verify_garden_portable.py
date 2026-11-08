"""Exercise both allowed garden projects after an independent import on F:."""

import json
import os
from pathlib import Path
import shutil
import sys
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_model_previews import port
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]


def main():
    out = Path(sys.argv[1]).resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N06" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = out / f"garden_{mode}.zip"
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            for name in ("resources/catalog/gardens.json", "scripts/builder/garden_plan.gd", "scripts/builder/garden_runtime.gd"):
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            assert not any("Garden_greenhouse_kit" in name for name in names)
            source = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert source["garden"]["enabled"] and sum(item.get("garden", {}).get("enabled", False) for item in source["objects"]) == 2
            assert not ({"garden_account", "crop_progress", "garden_receipts"} & source.keys())
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_garden_export.gd", target / "verify_garden.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "1600", "--script", "res://verify_garden.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE GARDEN: 6 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: garden {mode} {label}", flush=True)
        results.append({"mode": mode, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
