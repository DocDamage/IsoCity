"""Run the authored café and its recipes in independently imported projects."""

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
    destination = ROOT.parent / "IsoCity-portable-validation" / "N08" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = out / f"kitchen_{mode}.zip"
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(name.startswith((".godot/", "output/")) for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and sha(content) == entry["sha256"], entry["path"]
            for name in ("resources/catalog/cooking.json", "scripts/builder/activity_stock.gd",
                         "scripts/builder/cooking_plan.gd", "scripts/builder/cooking_runtime.gd",
                         "scripts/builder/business_runtime.gd", "scripts/builder/business_visits.gd"):
                assert archive.read(name) == (ROOT / name).read_bytes(), name
            assert any("Bread_Basket" in name and name.endswith(".png") for name in names)
            assert not any("Kitchen_cookware_kit" in name for name in names)
            data = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert data["cooking"]["enabled"] and len(data["objects"][0]["interior"]["objects"]) == 4
            assert not ({"kitchen_accounts", "cooking_jobs", "receipts"} & data.keys())
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_cooking_export.gd", target / "verify_cooking.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        runs = []
        for label, flags in (
            ("import", ["--headless", "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "2000", "--script", "res://verify_cooking.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE COOKING: 8 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: cooking {mode} {label}", flush=True)
        results.append({"mode": mode, "destination": str(target), "package_sha256": digest,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    (out / "portable_projects.json").write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
