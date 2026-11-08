"""Import and play the authored court in independent source projects."""
import hashlib
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

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    out = Path(sys.argv[1]).resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N10" / uuid.uuid4().hex
    reports = []
    for mode in ("2d", "3d"):
        package = out / f"sports_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) or "Gym_fitness_kit/" in name for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            for name in ("resources/catalog/fitness.json", "scripts/builder/fitness_plan.gd",
                         "scripts/builder/fitness_runtime.gd", "scripts/builder/fitness_court.gd",
                         "scripts/builder/fitness_motion.gd", "scripts/builder/fitness_view.gd"):
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            assert "2d:Reviewed_village_football_0" in manifest["assets"]
            assert any(path.endswith("/Reviewed_village_football_0_SE.png") for path in names)
            data = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert data["fitness"]["enabled"] and data["objects"][0]["fitness"]["open_hour"] == 20
            assert not ({"booking", "session", "history"} & data.keys())
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_fitness_export.gd", target / "verify_fitness.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "1800", "--script", "res://verify_fitness.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE FITNESS: 10 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: fitness {mode} {label}", flush=True)
        reports.append({"mode": mode, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(reports, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
