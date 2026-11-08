"""Open and exercise local deliveries in independently relocated Godot exports."""
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


def inspect(package, target, mode):
    with zipfile.ZipFile(package) as archive:
        assert all((target / name).resolve().is_relative_to(target.resolve()) for name in archive.namelist())
        assert not any(name.startswith((".godot/", "output/")) for name in archive.namelist())
        manifest = json.loads(archive.read("export-manifest.json"))
        for entry in manifest["files"]:
            data = archive.read(entry["path"])
            assert len(data) == entry["bytes"] and sha(data) == entry["sha256"], entry["path"]
        cargo = "2d:crate" if mode == "2d" else "3d:HanX_Shop/Cardboard_Boxes"
        van = "2d:Delivery_Van" if mode == "2d" else "3d:HanX_Traffic/Van_Delivery"
        assert {cargo, van}.issubset(manifest["assets"])
        for path in ["resources/catalog/deliveries.json", *(f"scripts/builder/delivery_{n}.gd" for n in ("plan", "runtime", "view"))]:
            assert sha(archive.read(path)) == sha((ROOT / path).read_bytes()), path
        source = json.loads(archive.read("city-source.json"))["documents"][mode]
        placed = {item["uid"]: item for item in source["objects"]}
        assert placed["pickup"]["delivery_contract"]["destination"] == "drop"
        assert placed["pickup"]["delivery_site"]["stock"] == {"parcels": 8}
        assert all(item["asset"] != cargo for item in source["objects"]), "Cargo should be a future runtime dependency."
        assert source["economy_account"]["cash"] == 900
        archive.extractall(target)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("packages", type=Path)
    parser.add_argument("--visible-import", action="store_true")
    args = parser.parse_args()
    packages = args.packages.resolve()
    engine = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not engine:
        raise RuntimeError("Set GODOT_BIN to the Godot console executable.")
    destination = ROOT.parent / "IsoCity-portable-validation" / "N03" / uuid.uuid4().hex
    results = []
    for mode in ("2d", "3d"):
        package = packages / f"delivery_{mode}.zip"
        digest = sha(package.read_bytes())
        target = destination / mode
        target.mkdir(parents=True)
        inspect(package, target, mode)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools/test_local_delivery_export.gd", target / "verify_delivery.gd")
        project = target / "project.godot"
        initial = settings(project.read_bytes())
        import_flags = [] if args.visible_import else ["--headless"]
        import_flags += ["--editor", "--import", "--accessibility-driver", "dummy", "--lsp-port", port(), "--dap-port", port()]
        for label, flags in (
            ("import", import_flags),
            ("runtime", ["--headless", "--fixed-fps", "60", "--quit-after", "15000", "--script", "res://verify_delivery.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            if label == "import" and os.name == "nt":
                command = run_import(engine, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
            else:
                command = [engine, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
                stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                assert "PORTABLE LOCAL DELIVERIES: 6 checks, 0 failures" in log.read_text(encoding="utf-8")
            assert settings(project.read_bytes()) == initial and sha(package.read_bytes()) == digest
            results.append({"mode": mode, "package": str(package), "package_sha256": digest, "stage": label,
                            "command": command, "log": str(log), "sha256": sha(log.read_bytes())})
            print(f"PASS: {mode} {label}", flush=True)
        (packages / "portable_projects.json").write_text(
            json.dumps({"destination": str(destination), "results": results}, indent=2) + "\n", encoding="utf-8"
        )


if __name__ == "__main__":
    main()
