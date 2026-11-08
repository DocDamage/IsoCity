"""Verify power packages in fresh Godot projects alongside the checkout."""
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


def inspect(package, target, mode):
    with zipfile.ZipFile(package) as archive:
        names = archive.namelist()
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
        assert not any(name.startswith((".godot/", "output/")) for name in names)
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            data = archive.read(entry["path"])
            assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
        source = json.loads(archive.read("city-source.json"))["documents"][mode]
        assert source["utilities"] == {"power": True}
        assert len(source["utility_nodes"]) == 7 and len(source["utility_edges"]) == 6
        assert not ({"stock", "report", "allocations"} & source.keys())
        placed = {item["uid"]: item for item in source["objects"]}
        upper = placed["home"]["interior"]["floors"][0]["room"]
        assert {item["asset"] for item in (*placed.values(), *upper["objects"])}.issubset(manifest["assets"])
        required = [
            "resources/catalog/power_profiles.json",
            "resources/previews_imported/Added_rendered_power_plants_battery_storage_2dd8800d.png",
            *(f"scripts/builder/utility_{name}.gd" for name in ("profiles", "plan", "runtime")),
        ]
        if mode == "2d":
            required.append("resources/previews_imported/Added_rendered_power_plants_gas_plant_18bbafda.png")
        else:
            required.append("resources/previews_3d/HanX_Construction/Generator.png")
        for path in required:
            assert sha(archive.read(path)) == sha((ROOT / path).read_bytes()), path
        archive.extractall(target)
        return len(manifest["files"])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    parser.add_argument("--visible-import", action="store_true")
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N05" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"power_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        files = inspect(package, target, mode)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_power_export.gd", target / "verify_power.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        import_flags = [] if args.visible_import else ["--headless"]
        import_flags += ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]
        for label, flags in (
            ("import", import_flags),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "1200", "--script", "res://verify_power.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE POWER NETWORK: 8 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "package_sha256": digest,
                            "stage": label, "command": command, "log": str(log), "sha256": sha(log.read_bytes()),
                            "manifest_files_verified": files})
            print(f"PASS: power {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
