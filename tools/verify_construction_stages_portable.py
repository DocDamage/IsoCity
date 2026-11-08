"""Verify construction stages in independently relocated 2D and 3D projects."""

import argparse
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_companion_portable import settings
from verify_construction_costs_portable import run_import
from verify_model_previews import port
from verify_school_portable import sha

ROOT = Path(__file__).resolve().parents[1]
CATALOG = "resources/catalog/construction_stages.json"


def inspect(package, target, mode):
    catalog = json.loads((ROOT / CATALOG).read_bytes())
    assets = {entry["asset"] for recipe in catalog["stages"].values() for entry in recipe}
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
        assert not any(name.startswith((".godot/", "output/")) for name in names)
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            data = archive.read(entry["path"])
            assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
        assert assets.issubset(manifest["assets"])
        required = [CATALOG, *(f"scripts/builder/{name}.gd" for name in
                               ("asset_instance", "zone_plan", "zone_stage_plan", "zone_runtime", "zone_visual_2d"))]
        for asset in sorted(assets):
            model = asset.removeprefix("3d:")
            required.extend((f"scenes/items_3d/{model}.tscn", f"resources/previews_3d/{model}.png"))
        for path in required:
            assert sha(archive.read(path)) == sha((ROOT / path).read_bytes()), path
        source = json.loads(archive.read("city-source.json"))["documents"][mode]
        assert [lot["stage"] for lot in source["zones"]] == [1, 0]
        assert not source["objects"] and source["economy_account"]["cash"] == 25000
        archive.extractall(target)
        return {"manifest_files_verified": len(manifest["files"]), "stage_assets": sorted(assets)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    parser.add_argument("--visible-import", action="store_true")
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "I17" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"construction_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        report = inspect(package, target, mode)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_construction_stages_export.gd", target / "verify_construction.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        import_flags = [] if args.visible_import else ["--headless"]
        import_flags += ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]
        for label, flags in (
            ("import", import_flags),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "16000", "--script", "res://verify_construction.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            if label == "import" and os.name == "nt":
                command = run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
            else:
                command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
                stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE CONSTRUCTION STAGES: 12 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "package_sha256": digest, "stage": label,
                            "command": command, "log": str(log), "sha256": sha(log.read_bytes()), **report})
            print(f"PASS: construction {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
