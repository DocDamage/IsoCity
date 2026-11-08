"""Validate road rerouting in allowed exports relocated outside the checkout."""
import argparse
import hashlib
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

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    parser.add_argument("--diagnostics", action="store_true")
    parser.add_argument("--visible-import", action="store_true")
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    ticket = "U19" if args.diagnostics else "I12"
    prefix = "diagnostics" if args.diagnostics else "reroute"
    destination = ROOT.parent / "IsoCity-portable-validation" / ticket / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"{prefix}_{mode}.zip"
        target = destination / mode
        target.mkdir(parents=True)
        digest = sha(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = set(archive.namelist())
            assert all((target / name).resolve().is_relative_to(target.resolve()) for name in names)
            assert not any(".godot/" in name or name.startswith("output/") for name in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                data = archive.read(entry["path"])
                assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
            for name in (
                "scripts/builder/traffic_route_queue.gd", "scripts/builder/traffic_runtime.gd",
                "scripts/builder/transit_runtime.gd", "scripts/builder/transit_passengers.gd",
                "scripts/builder/service_runtime.gd", "scripts/builder/service_dispatch.gd",
            ):
                assert sha(archive.read(name)) == sha((ROOT / name).read_bytes()), name
            source = json.loads(archive.read("city-source.json"))["documents"][mode]
            assert source["traffic"]["population"] == 1 and len(source["roads"]) == 10
            assert source["objects"][-1]["uid"] == "bay" and source["objects"][-1]["traffic_parking"]
            assert not any(key in source for key in ("route_queue", "route_request", "bay_owners", "crews", "buses"))
            if args.diagnostics:
                assert not any(token in archive.read("city-source.json") for token in (b'"message_key"', b'"traffic_lane"', b'"simulation_diagnostics"'))
                scene = archive.read("city.tscn")
                assert b"simulation_diagnostic" not in scene and b"scripts/builder/studio.gd" not in scene
            if mode == "3d":
                previews = ["resources/previews_3d/HanX_Traffic/Car_Sedan.png",
                            "resources/previews_3d/HanX_Traffic/Road_Parking.png"]
            else:
                previews = [name for name in names if name.endswith(".png") and
                            ("Parking_Accessible" in name or "Sedan_Blue" in name)]
                assert len(previews) == 5
            for name in previews:
                assert sha(archive.read(name)) == sha((ROOT / name).read_bytes()), name
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_traffic_reroute_export.gd", target / "verify_reroute.gd")
        project = target / "project.godot"
        initial_settings = settings(project.read_bytes())
        import_flags = [] if args.visible_import else ["--headless"]
        for label, flags in (
            ("import", [*import_flags, "--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "10000", "--script", "res://verify_reroute.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            if label == "import" and os.name == "nt":
                run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
            else:
                stage([engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags], target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE REROUTE: 6 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial_settings and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "stage": label, "log": str(log),
                            "sha256": sha(log.read_bytes()), "package_sha256": digest})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
