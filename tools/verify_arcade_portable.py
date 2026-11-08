"""Import the exported arcade rooms and play both games in each."""
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
    destination = ROOT.parent / "IsoCity-portable-validation" / "N11" / uuid.uuid4().hex
    reports = []
    for mode in ("2d", "3d"):
        package = out / f"arcade_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            for name in ("resources/catalog/arcade.json", "scripts/builder/arcade_plan.gd",
                         "scripts/builder/arcade_runtime.gd", "scripts/builder/arcade_sprint.gd",
                         "scripts/builder/arcade_signals.gd", "scripts/builder/arcade_view.gd",
                         "scenes/builder/arcade_sprint.tscn", "scenes/builder/arcade_signals.tscn"):
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            for fixture in ("13_arcade_13_racer_blue", "19_arcade_19_dance_machine", "08_arcade_08_fighting_cabinet_2p"):
                assert f"3d:Supplemental_Arcade/{fixture}" in manifest["assets"]
                assert any(path.endswith(f"/{fixture}.glb") for path in names)
            assert any("Arcade_Machines_Pack_LowPoly/LICENSE.txt" in path for path in names)
            data = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert data["arcade"]["enabled"]
            assert sorted(item["arcade"]["game"] for item in data["objects"][0]["interior"]["objects"]) == [
                "auto", "auto", "signals", "signals"]
            assert not ({"session", "boards", "last_result"} & data.keys())
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_arcade_export.gd", target / "verify_arcade.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "3000", "--script", "res://verify_arcade.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE ARCADE: 8 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: arcade {mode} {label}", flush=True)
        reports.append({"mode": mode, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(reports, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
