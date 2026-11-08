"""Verify original and place-specific audio after fresh portable relocation."""
import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import shutil
import uuid
import zipfile

from verify_collection_portable import stage
from verify_construction_costs_portable import run_import

ROOT = Path(__file__).resolve().parents[1]
KINDS = ("traffic", "fountain", "birds", "shop", "interior",
         "school", "arcade", "workshop", "market", "harbor")


def digest(content):
    return sha256(content).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--place", type=Path, help="Verify place-specific packages from this directory")
    args = parser.parse_args()
    godot = os.environ.get("GODOT_BIN") or shutil.which("godot_console") or shutil.which("godot")
    if not godot:
        raise RuntimeError("Godot is required")
    destination = ROOT.parent / "IsoCity-portable-validation" / "I18" / uuid.uuid4().hex
    log_dir = args.place.resolve() if args.place else ROOT / "output" / "verification"
    log_dir.mkdir(parents=True, exist_ok=True)
    name = "place" if args.place else "ambience"
    source = log_dir if args.place else ROOT / "output"
    probe = "test_place_ambience_export.gd" if args.place else "test_ambience_export_runtime.gd"
    records = []
    for mode in ("2d", "3d"):
        target = destination / mode
        target.mkdir(parents=True)
        package = source / f"{name}_{mode}.zip"
        package_hash = digest(package.read_bytes())
        with zipfile.ZipFile(package) as archive:
            names = archive.namelist()
            assert all((target / entry).resolve().is_relative_to(target) for entry in names)
            assert not any(entry.startswith((".godot/", "output/")) for entry in names)
            manifest = json.loads(archive.read("export-manifest.json"))
            for entry in manifest["files"]:
                content = archive.read(entry["path"])
                assert len(content) == entry["bytes"] and digest(content) == entry["sha256"], entry["path"]
            for kind in KINDS:
                for suffix in (".wav", ".wav.import"):
                    path = f"assets/audio/{kind}{suffix}"
                    assert archive.read(path) == (ROOT / path).read_bytes(), path
            assert archive.read("assets/audio/LICENSE.txt") == (ROOT / "assets/audio/LICENSE.txt").read_bytes()
            archive.extractall(target)
        assert not (target / ".godot").exists()
        shutil.copyfile(ROOT / "tools" / probe, target / "verify_ambience.gd")
        command = run_import(godot, target, mode, windows_model_renderer="gl_compatibility", wait_for_windows=True)
        log = target / "verification_import.log"
        runs = [{"stage": "import", "command": command, "log": str(log), "sha256": digest(log.read_bytes())}]
        print(f"PASS: {name} ambience {mode} import", flush=True)
        for label, flags in (
            ("runtime", ["--headless", "--disable-render-loop", "--fixed-fps", "60", "--quit-after", "4000",
                         "--script", "res://verify_ambience.gd"]),
            ("visible_main", ["--disable-vsync", "--quit-after", "30"]),
        ):
            command = [godot, "--path", str(target), "--log-file", str(target / f"engine_{label}.log"), *flags]
            stage(command, target, label, 180)
            log = target / f"verification_{label}.log"
            if label == "runtime":
                expected = "PORTABLE PLACE AMBIENCE: 18 checks, 0 failures" if args.place else (
                    f"AMBIENCE EXPORT: {22 if mode == '3d' else 21} checks, 0 failures")
                assert expected in log.read_text(encoding="utf-8"), log
            assert digest(package.read_bytes()) == package_hash
            runs.append({"stage": label, "command": command, "log": str(log), "sha256": digest(log.read_bytes())})
            print(f"PASS: {name} ambience {mode} {label}", flush=True)
        records.append({"mode": mode, "destination": str(target), "package_sha256": package_hash,
                        "manifest_files_verified": len(manifest["files"]), "results": runs})
    report = destination / f"{name}_portable_projects.json"
    report.write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
    print(f"Ambience verification report: {report}")
    print(f"Ambience projects retained for inspection on {ROOT.drive}: {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
